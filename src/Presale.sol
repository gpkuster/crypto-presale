// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract Presale is Ownable {
    // Mandatory statement for using libraries
    using SafeERC20 for IERC20;

    address public usdtAddress;
    address public usdcAddress;
    address public fundsReceiverAddress;
    uint256 public maxSellingAmount;
    uint256 public startingTime;
    uint256 public endingTime;
    uint256[][3] public phases;

    uint256 totalSold;
    uint256 public currentPhase;

    mapping(address => bool) public isBlackListed;
    mapping(address => uint256) public userTokenBalance;

    event TokenBought(address user, uint256 amount_);

    constructor(
        address usdtAddress_,
        address usdcAddress_,
        address fundsReceiverAddress_,
        uint256 maxSellingAmount_,
        uint256 startingTime_,
        uint256 endingTime_,
        uint256[][3] memory phases_
    ) Ownable(msg.sender) {
        require(endingTime_ > startingTime_, "Ending time must be greater than starting time.");
        usdtAddress = usdtAddress_;
        usdcAddress = usdcAddress_;
        fundsReceiverAddress = fundsReceiverAddress_;
        maxSellingAmount = maxSellingAmount_;
        startingTime = startingTime_;
        endingTime = endingTime_;
        phases = phases_;
    }

    /**
     * Used to blacklist users
     * @param user_ The address of the user to blacklist
     */
    function blackList(address user_) external onlyOwner {
        isBlackListed[user_] = true;
    }

    /**
     * Used to remove users from the blacklist
     * @param user_ The address of the user to remove
     */
    function removeFromBlackList(address user_) external onlyOwner {
        isBlackListed[user_] = false;
    }

    /**
     * Used to check current phase
     * @param amount_ The amount used to check in which phase the presale is
     */
    function checkCurrentPhase(uint256 amount_) private returns (uint256) {
        if ((totalSold + amount_ > phases[currentPhase][0]) || (block.timestamp >= phases[currentPhase][2])) {
            currentPhase++;
        }
        return currentPhase;
    }

    /**
     * Used to buy tokens with stable coins
     * @param tokenUsedToBuy_ the address of the token used to buy
     * @param amount_ the amount of tokens for buying
     */
    function buyWithStable(address tokenUsedToBuy_, uint256 amount_) external {
        require(!isBlackListed[msg.sender], "User is blacklisted");
        require(block.timestamp >= startingTime, "Presale not started yet");
        require(tokenUsedToBuy_ == usdtAddress || tokenUsedToBuy_ == usdcAddress, "Incorrect token");

        uint8 stableDecimals = 6; // both USDT and USDC
        uint256 tokenAmountToReceive = amount_ * 10 ** (18 - stableDecimals) / phases[currentPhase][1];

        checkCurrentPhase(amount_);
        totalSold += tokenAmountToReceive;
        require(totalSold <= maxSellingAmount, "Sold out");

        userTokenBalance[msg.sender] += tokenAmountToReceive;

        IERC20(tokenUsedToBuy_).safeTransferFrom(msg.sender, fundsReceiverAddress, amount_);
        emit TokenBought(msg.sender, amount_);
    }

    /**
     * Used to withdraw tokens
     * @param tokenAddress_ The address of the token to withdraw
     * @param amount_ The amount to withdraw
     */
    function emergencyERC20Withdraw(address tokenAddress_, uint256 amount_) external onlyOwner {
        // safeTransfer receives 3 parameters, but the first one is not needed
        IERC20(tokenAddress_).safeTransfer(msg.sender, amount_);
    }

    /**
     * Used to withdraw ETH
     */
    function emergencyETHWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success,) = msg.sender.call{value: balance}("");
        require(success, "Transfer fail");
    }
}
