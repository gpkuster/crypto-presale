// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/Presale.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @notice Mock stablecoin with 6 decimals for USDT/USDC simulation
contract MockStable is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract PresaleTest is Test {
    Presale presale;
    MockStable usdt;
    MockStable usdc;

    address owner = address(0xA11CE);
    address buyer = address(0xB0B);
    address fundsReceiver = address(0xC0FFEE);

    uint256 constant START = 1000;
    uint256 constant END = 2000;

    function setUp() public {
        vm.startPrank(owner);
        usdt = new MockStable("Tether USD", "USDT");
        usdc = new MockStable("USD Coin", "USDC");

        Presale.Phase[] memory _phases = new Presale.Phase[](3);
        // cap, price, endTime
        _phases[0] = Presale.Phase({
            cap: 1_000 ether,
            price: 1_000_000, // 1 USDC per token
            endTime: START + 100
        });
        _phases[1] = Presale.Phase({
            cap: 2_000 ether,
            price: 2_000_000, // 2 USDC per token
            endTime: START + 200
        });
        _phases[2] = Presale.Phase({
            cap: 3_000 ether,
            price: 3_000_000, // 3 USDC per token
            endTime: START + 300
        });

        presale = new Presale(
            address(usdt),
            address(usdc),
            fundsReceiver,
            3_000 ether,
            START,
            END,
            _phases
        );

        vm.stopPrank();

        // fund buyer with stables
        usdt.mint(buyer, 1_000_000_000);
        usdc.mint(buyer, 1_000_000_000);
    }

    /* ------------------------ Constructor ------------------------ */

    function testConstructorSetsValues() public {
        assertEq(presale.usdtAddress(), address(usdt));
        assertEq(presale.usdcAddress(), address(usdc));
        assertEq(presale.fundsReceiverAddress(), fundsReceiver);
        assertEq(presale.maxSellingAmount(), 3_000 ether);
        assertEq(presale.startingTime(), START);
        assertEq(presale.endingTime(), END);
        assertEq(presale.phasesCount(), 3);
        assertEq(presale.getCurrentPhase(), 0);
    }

    /* ------------------------ Buying ------------------------ */

    function testBuyWithUSDT_basicFlow() public {
        vm.warp(START + 1);
        vm.startPrank(buyer);
        usdt.approve(address(presale), type(uint256).max);

        uint256 stableAmount = 1_000_000; // 1 USDT
        // price = 1 USDT per token => expect 1 token (1e18)
        presale.buyWithStable(address(usdt), stableAmount);

        assertEq(presale.userTokenBalance(buyer), 1e18);
        assertEq(presale.totalSold(), 1e18);
        assertEq(usdt.balanceOf(fundsReceiver), stableAmount);
    }

    function testBuyWithUSDC_basicFlow() public {
        vm.warp(START + 1);
        vm.startPrank(buyer);
        usdc.approve(address(presale), type(uint256).max);

        uint256 stableAmount = 2_000_000; // 2 USDC
        presale.buyWithStable(address(usdc), stableAmount);

        // price = 1 USDC per token (phase 0) => 2 tokens
        assertEq(presale.userTokenBalance(buyer), 2e18);
        assertEq(presale.totalSold(), 2e18);
        assertEq(usdc.balanceOf(fundsReceiver), stableAmount);
    }

    /* ------------------------ Phase advancement ------------------------ */

    function testPhaseAdvanceByCap() public {
        vm.warp(START + 10);
        vm.startPrank(buyer);
        usdt.approve(address(presale), type(uint256).max);

        // buy enough to exceed phase 0 cap (1,000 tokens)
        uint256 stableAmount = 1_000_000_000; // 1000 USDT => 1000 tokens
        presale.buyWithStable(address(usdt), stableAmount);

        assertEq(presale.totalSold(), 1_000 ether);
        assertEq(presale.currentPhase(), 1, "Phase should have advanced");
    }

    function testPhaseAdvanceByTime() public {
        vm.warp(START + 150); // after first phase endTime (100)
        vm.startPrank(buyer);
        usdt.approve(address(presale), type(uint256).max);
        presale.buyWithStable(address(usdt), 1_000_000); // 1 USDT

        // Should start in phase 1 due to time passed
        assertEq(presale.currentPhase(), 1);
    }

    function testFinalPhaseDoesNotOverflow() public {
        vm.warp(START + 400); // after all endTimes
        vm.startPrank(buyer);
        usdt.approve(address(presale), type(uint256).max);

        // Buy in final phase
        presale.buyWithStable(address(usdt), 1_000_000);
        assertEq(presale.currentPhase(), 2);

        // Keep buying — should never overflow
        presale.buyWithStable(address(usdt), 10_000_000);
        assertEq(presale.currentPhase(), 2);
    }

    /* ------------------------ Access control ------------------------ */

    function testBlacklistBlocksPurchase() public {
        vm.startPrank(owner);
        presale.blackList(buyer);
        vm.stopPrank();

        vm.warp(START + 10);
        vm.startPrank(buyer);
        usdt.approve(address(presale), 1_000_000);
        vm.expectRevert("User blacklisted");
        presale.buyWithStable(address(usdt), 1_000_000);
    }

    function testRemoveBlacklistAllowsPurchase() public {
        vm.startPrank(owner);
        presale.blackList(buyer);
        presale.removeFromBlackList(buyer);
        vm.stopPrank();

        vm.warp(START + 10);
        vm.startPrank(buyer);
        usdt.approve(address(presale), 1_000_000);
        presale.buyWithStable(address(usdt), 1_000_000);
        assertEq(presale.userTokenBalance(buyer), 1e18);
    }

    function testOnlyOwnerCanWithdrawERC20() public {
        usdt.mint(address(presale), 100);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer));
        presale.emergencyERC20Withdraw(address(usdt), 100);
        vm.stopPrank();

        vm.startPrank(owner);
        presale.emergencyERC20Withdraw(address(usdt), 100);
        vm.stopPrank();

        assertEq(usdt.balanceOf(owner), 100);
    }

    /* ------------------------ Edge cases ------------------------ */

    function testRevertBeforeStart() public {
        vm.warp(START - 1);
        vm.startPrank(buyer);
        usdt.approve(address(presale), 1_000_000);
        vm.expectRevert("Presale not started");
        presale.buyWithStable(address(usdt), 1_000_000);
    }

    function testRevertAfterEnd() public {
        vm.warp(END + 1);
        vm.startPrank(buyer);
        usdt.approve(address(presale), 1_000_000);
        vm.expectRevert("Presale ended");
        presale.buyWithStable(address(usdt), 1_000_000);
    }

    function testRevertIfSoldOut() public {
        vm.warp(START + 1);
        vm.startPrank(buyer);
        usdt.approve(address(presale), type(uint256).max);

        // buy exactly maxSellingAmount in tokens (3k)
        uint256 stableToMax = 3_000_000_000; // depends on price, but let's overshoot
        deal(address(usdt), buyer, 3_000_000_000);
        presale.buyWithStable(address(usdt), stableToMax);

        // next buy should revert
        vm.expectRevert("Sold out or exceeds max sell amount");
        presale.buyWithStable(address(usdt), 1_000_000);
    }

    function testChangeFundsReceiverOnlyOwner() public {
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer));
        presale.setFundsReceiver(address(123));
        vm.stopPrank();

        vm.startPrank(owner);
        presale.setFundsReceiver(address(123));
        assertEq(presale.fundsReceiverAddress(), address(123));
    }

    function testWithdrawETH() public {
        vm.deal(address(presale), 10 ether);
        vm.startPrank(owner);
        presale.emergencyETHWithdraw();
        assertEq(address(presale).balance, 0);
        assertEq(owner.balance, 10 ether);
    }
}