// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract Presale is Ownable {
    using SafeERC20 for IERC20;

    address public usdtAddress;
    address public usdcAddress;
    address public fundsReceiverAddress;
    uint256 public maxSellingAmount;
    uint256 public startingTime;
    uint256 public endingTime;
    uint256[][3] public phases;
    mapping (address => bool) public isBlackListed;

    constructor(address usdtAddress_, address usdcAddress_, address fundsReceiverAddress_, uint256 maxSellingAmount_, uint256 startingTime_, uint256 endingTime_, uint256[][3] memory phases_) Ownable(msg.sender) {
        require(endingTime_ > startingTime_, "Starting time must be greater than ending time.");
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
    function blackList(address user_) onlyOwner external {
        isBlackListed[user_] = true;
    }

    /**
     * Used to remove users from the blacklist 
     * @param user_ The address of the user to remove
     */
    function removeFromBlackList(address user_) onlyOwner external {
        isBlackListed[user_] = false;
    }


    function buyWithStable() onlyOwner() external {
        require(!isBlackListed[msg.sender], "User is blacklisted");
        require(block.timestamp >= startingTime, "Presale not started yet");
    }

    function emergencyERC20Withdraw(address tokenAddress_, uint256 amount_) onlyOwner external {
        IERC20(tokenAddress_).safeTransfer(msg.sender, amount_);
    }

    function emergencyETHWithdraw(address tokenAddress_, uint256 amount_) onlyOwner external {
        uint256 balance = address(this).balance;
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Transfer fail");
    }

    

}
