// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Presale
 * @notice Simple presale that accepts USDT/USDC and credits users with token balances (18-decimals).
 *
 * PHASE model:
 * - phases is an array of Phase structs
 * - Phase.cap: cumulative cap (in token units with 18 decimals) up to which this phase is active
 * - Phase.price: price (stablecoin units with 6 decimals) per 1 token (i.e. stable amount required to buy 1 token, expressed with 6 decimals)
 * - Phase.endTime: unix timestamp; if reached, phase can advance
 *
 * NOTE about price arithmetic:
 * - stablecoins are assumed to have 6 decimals (USDT/USDC)
 * - tokens sold are tracked with 18 decimals
 * - tokenAmount = stableAmount * 1e18 / price
 */
contract Presale is Ownable {
    using SafeERC20 for IERC20;

    struct Phase {
        uint256 cap;      // cumulative cap in tokens (18 decimals)
        uint256 price;    // stable units (6 decimals) per token
        uint256 endTime;  // unix timestamp when phase ends
    }

    address public immutable usdtAddress;
    address public immutable usdcAddress;
    address public fundsReceiverAddress;

    uint256 public maxSellingAmount; // max tokens to sell (18 decimals)
    uint256 public startingTime;
    uint256 public endingTime;

    Phase[] public phases;

    uint256 public totalSold;        // tokens sold so far (18 decimals)
    uint256 public currentPhase;     // index in phases[]

    mapping(address => bool) public isBlackListed;
    mapping(address => uint256) public userTokenBalance; // credited token balances (18 decimals)

    // emitted when a user buys: stableAmount is in stable decimals (6), tokenAmount is 18 decimals
    event TokenBought(address indexed user, uint256 stableAmount, uint256 tokenAmount);
    event PhaseAdvanced(uint256 oldPhase, uint256 newPhase);
    event FundsReceiverUpdated(address oldReceiver, address newReceiver);

    /**
     * @param usdtAddress_ USDT token address (6 decimals)
     * @param usdcAddress_ USDC token address (6 decimals)
     * @param fundsReceiverAddress_ address that receives the stablecoins
     * @param maxSellingAmount_ max number of tokens to sell (18 decimals)
     * @param startingTime_ presale start unix timestamp
     * @param endingTime_ presale end unix timestamp
     * @param phases_ array of Phase structs (cap, price, endTime). Must be non-empty.
     */
    constructor(
        address usdtAddress_,
        address usdcAddress_,
        address fundsReceiverAddress_,
        uint256 maxSellingAmount_,
        uint256 startingTime_,
        uint256 endingTime_,
        Phase[] memory phases_
    ) Ownable(msg.sender) {
        require(endingTime_ > startingTime_, "Ending time must be > starting time");
        require(phases_.length > 0, "At least one phase required");
        require(maxSellingAmount_ > 0, "maxSellingAmount required");

        // sanity: ensure phase caps are non-decreasing and endTimes make sense
        for (uint256 i = 0; i < phases_.length; i++) {
            if (i > 0) {
                require(phases_[i].cap >= phases_[i - 1].cap, "phase caps must be non-decreasing");
                require(phases_[i].endTime >= phases_[i - 1].endTime, "phase endTimes must be non-decreasing");
            }
            require(phases_[i].price > 0, "phase price must be > 0");
        }

        usdtAddress = usdtAddress_;
        usdcAddress = usdcAddress_;
        fundsReceiverAddress = fundsReceiverAddress_;
        maxSellingAmount = maxSellingAmount_;
        startingTime = startingTime_;
        endingTime = endingTime_;

        // copy phases into storage
        for (uint256 i = 0; i < phases_.length; i++) {
            phases.push(phases_[i]);
        }
    }

    /* ========== OWNER ACTIONS ========== */

    /// @notice blacklists an address
    function blackList(address user_) external onlyOwner {
        isBlackListed[user_] = true;
    }

    /// @notice removes an address from blacklist
    function removeFromBlackList(address user_) external onlyOwner {
        isBlackListed[user_] = false;
    }

    /// @notice update funds receiver
    function setFundsReceiver(address newReceiver) external onlyOwner {
        require(newReceiver != address(0), "zero address");
        emit FundsReceiverUpdated(fundsReceiverAddress, newReceiver);
        fundsReceiverAddress = newReceiver;
    }

    /* ========== PHASE HELPERS ========== */

    /// @notice returns number of phases configured
    function phasesCount() external view returns (uint256) {
        return phases.length;
    }

    /// @notice view function that returns the current phase index (does not modify state)
    function getCurrentPhase() public view returns (uint256) {
        return currentPhase;
    }

    /**
     * @notice Advances phase if needed based on current totalSold or time.
     * Uses >= for cap comparison so exact-cap purchases advance the phase.
     * Will not advance beyond the last phase.
     */
    function advancePhaseIfNeeded() internal {
        while (currentPhase < phases.length - 1) {
            bool capReached = totalSold >= phases[currentPhase].cap;
            bool timeExpired = block.timestamp >= phases[currentPhase].endTime;
            if (capReached || timeExpired) {
                uint256 old = currentPhase;
                currentPhase++;
                emit PhaseAdvanced(old, currentPhase);
            } else {
                break;
            }
        }
    }

    /* ========== BUY ========== */

    /**
     * @notice Buy tokens with USDT or USDC stablecoin.
     * @param tokenUsedToBuy_ address of stable token (must be usdtAddress or usdcAddress)
     * @param stableAmount_ amount of stable (6 decimals) the buyer pays (e.g. 1 USDC == 1e6)
     */
    function buyWithStable(address tokenUsedToBuy_, uint256 stableAmount_) external {
        require(!isBlackListed[msg.sender], "User blacklisted");
        require(block.timestamp >= startingTime, "Presale not started");
        require(block.timestamp <= endingTime, "Presale ended");
        require(tokenUsedToBuy_ == usdtAddress || tokenUsedToBuy_ == usdcAddress, "Unsupported stable token");
        require(stableAmount_ > 0, "Amount must be > 0");
        require(fundsReceiverAddress != address(0), "Funds receiver not set");

        // First: advance phase if time-based triggers occurred
        advancePhaseIfNeeded();

        // Compute token amount using current phase price
        // stableAmount_ (6 decimals) and ph.price (6 decimals) => stableAmount_/ph.price is token units (no decimals)
        // Multiply by 1e18 to produce token units with 18 decimals.
        Phase memory ph = phases[currentPhase];

        // tokenAmountToReceive = stableAmount_ * 1e18 / price
        uint256 tokenAmountToReceive = (stableAmount_ * 1e18) / ph.price;
        require(tokenAmountToReceive > 0, "Amount too small for 1 token at current price");

        // Effects: update totals first (Checks-Effects-Interactions)
        uint256 newTotal = totalSold + tokenAmountToReceive;
        require(newTotal <= maxSellingAmount, "Sold out or exceeds max sell amount");

        totalSold = newTotal;
        userTokenBalance[msg.sender] += tokenAmountToReceive;

        // After updating total sold, check caps/time again to advance phases if thresholds crossed
        advancePhaseIfNeeded();

        // Interaction: transfer stable tokens from buyer -> fundsReceiver
        IERC20(tokenUsedToBuy_).safeTransferFrom(msg.sender, fundsReceiverAddress, stableAmount_);

        emit TokenBought(msg.sender, stableAmount_, tokenAmountToReceive);
    }

    /* ========== EMERGENCY / OWNER WITHDRAWALS ========== */

    /**
     * @notice Owner can withdraw any ERC20 accidentally sent to this contract.
     * @param tokenAddress_ token contract address
     * @param amount_ amount to withdraw
     */
    function emergencyERC20Withdraw(address tokenAddress_, uint256 amount_) external onlyOwner {
        require(tokenAddress_ != address(0), "zero token");
        IERC20(tokenAddress_).safeTransfer(msg.sender, amount_);
    }

    /**
     * @notice Owner can withdraw ETH accidentally sent to the contract.
     */
    function emergencyETHWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Transfer failed");
    }

    /* ========== VIEW HELPERS ========== */

    /// @notice read phase info
    function getPhase(uint256 index) external view returns (uint256 cap, uint256 price, uint256 endTime) {
        require(index < phases.length, "index OOB");
        Phase memory p = phases[index];
        return (p.cap, p.price, p.endTime);
    }
}
