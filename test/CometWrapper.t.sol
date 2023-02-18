// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {BaseTest, CometHelpers, CometWrapper, ERC20, ICometRewards} from "./BaseTest.sol";

contract CometWrapperTest is BaseTest {
    function setUp() public override {
        super.setUp();

        vm.prank(cusdcHolder);
        comet.transfer(alice, 10_000e6);
        assertGt(comet.balanceOf(alice), 999e6);

        vm.prank(cusdcHolder);
        comet.transfer(bob, 10_000e6);
        assertGt(comet.balanceOf(bob), 999e6);
    }

    function test__consructor() public {
        assertEq(cometWrapper.trackingIndexScale(), comet.trackingIndexScale());
        assertEq(address(cometWrapper.comet()), address(comet));
        assertEq(address(cometWrapper.cometRewards()), address(cometRewards));
        assertEq(address(cometWrapper.asset()), address(comet));
        assertEq(cometWrapper.decimals(), comet.decimals());
        assertEq(cometWrapper.name(), "Wrapped Comet USDC");
        assertEq(cometWrapper.symbol(), "WcUSDCv3");
        assertEq(cometWrapper.totalSupply(), cometWrapper.INITIAL_MINT());
        assertEq(cometWrapper.totalAssets(), cometWrapper.INITIAL_MINT() - 1);
        assertGt(cometWrapper.underlyingPrincipal(), 0);
    }

    function test__constructorRevertsOnInvalidComet() public {
        // reverts on zero address
        vm.expectRevert();
        new CometWrapper(ERC20(address(0)), cometRewards, "Name", "Symbol");

        // reverts on non-zero address that isn't ERC20 and Comet
        vm.expectRevert();
        new CometWrapper(ERC20(address(1)), cometRewards, "Name", "Symbol");

        // reverts on ERC20-only contract
        vm.expectRevert();
        new CometWrapper(usdc, cometRewards, "Name", "Symbol");
    }

    function test__constructorRevertsOnInvalidCometRewards() public {
        // reverts on zero address
        vm.expectRevert(CometHelpers.ZeroAddress.selector);
        new CometWrapper(ERC20(address(comet)), ICometRewards(address(0)), "Name", "Symbol");

        // reverts on non-zero address that isn't CometRewards
        vm.expectRevert();
        new CometWrapper(ERC20(address(comet)), ICometRewards(address(1)), "Name", "Symbol");
    }

    function test__totalAssets() public {
        assertEq(cometWrapper.totalAssets(), cometWrapper.INITIAL_MINT() - 1);

        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(5_000e6, alice);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));
        skip(14 days);
        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));

        vm.startPrank(bob);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(5_000e6, bob);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));
        skip(14 days);
        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));
    }

    function test__nullifyInflationAttacks() public {
        assertEq(cometWrapper.totalAssets(), cometWrapper.INITIAL_MINT() - 1);

        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(5_000e6, alice);
        vm.stopPrank();

        uint256 oldTotalAssets = cometWrapper.totalAssets();
        assertEq(oldTotalAssets, comet.balanceOf(wrapperAddress));

        // totalAssets can not be manipulated, effectively nullifying inflation attacks
        vm.prank(bob);
        comet.transfer(wrapperAddress, 5_000e6);
        // totalAssets does not change when doing a direct transfer
        assertEq(cometWrapper.totalAssets(), oldTotalAssets);
        assertLt(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));
    }

    function test__deposit() public {
        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(5_000e6, alice);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));
        // Account for rounding errors that lead to difference of 1
        assertEq(cometWrapper.maxWithdraw(alice) - 1, comet.balanceOf(alice));

        skip(14 days);
        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));
        // Account for rounding errors that lead to difference of 1
        assertEq(cometWrapper.maxWithdraw(alice) - 1, comet.balanceOf(alice));

        vm.startPrank(bob);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(7_777e6, bob);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));
        uint256 totalAssets = cometWrapper.maxWithdraw(alice) + cometWrapper.maxWithdraw(bob);
        // Alice and Bob should be able to withdraw all their assets without issue
        assertLe(totalAssets, cometWrapper.totalAssets());
    }

    function test__withdraw() public {
        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(9_101e6, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(2_555e6, bob);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));

        skip(14 days);
        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));

        vm.prank(alice);
        cometWrapper.withdraw(173e6, alice, alice);
        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));

        skip(500 days);
        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));

        uint256 totalAssets = cometWrapper.maxWithdraw(alice) + cometWrapper.maxWithdraw(bob);
        assertLe(totalAssets, cometWrapper.totalAssets());

        vm.startPrank(alice);
        cometWrapper.withdraw(cometWrapper.maxWithdraw(alice), alice, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        // Due to rounding errors when updating principal, sometimes maxWithdraw may be off by 1
        // This edge case appears when zeroing out the assets from the Wrapper contract
        cometWrapper.withdraw(cometWrapper.maxWithdraw(bob) - 1, bob, bob);
        vm.stopPrank();
    }

    function test__mint() public {
        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);
        cometWrapper.mint(9_000e6, alice);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));
        assertEq(cometWrapper.balanceOf(alice), 9_000e6);
        assertEq(cometWrapper.maxRedeem(alice), cometWrapper.balanceOf(alice));

        vm.startPrank(bob);
        comet.allow(wrapperAddress, true);
        cometWrapper.mint(7_777e6, bob);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));
        assertEq(cometWrapper.balanceOf(bob), 7_777e6);
        assertEq(cometWrapper.maxRedeem(bob), cometWrapper.balanceOf(bob));

        uint256 totalAssets =
            cometWrapper.maxWithdraw(bob) + cometWrapper.maxWithdraw(alice) + cometWrapper.INITIAL_MINT();
        assertEq(totalAssets - 1, cometWrapper.totalAssets());

        vm.startPrank(bob);
        cometWrapper.withdraw(cometWrapper.maxWithdraw(bob), bob, bob);
        vm.stopPrank();

        vm.startPrank(alice);
        cometWrapper.withdraw(cometWrapper.maxWithdraw(alice) - 1, alice, alice);
        vm.stopPrank();
    }

    function test__redeem() public {
        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);
        cometWrapper.mint(9_000e6, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        comet.allow(wrapperAddress, true);
        cometWrapper.mint(7_777e6, bob);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));

        uint256 totalRedeems = cometWrapper.maxRedeem(alice) + cometWrapper.maxRedeem(bob) + cometWrapper.INITIAL_MINT();
        assertEq(totalRedeems, cometWrapper.totalSupply());

        skip(500 days);

        // All users can fully redeem shares
        vm.startPrank(alice);
        cometWrapper.redeem(cometWrapper.maxRedeem(alice), alice, alice);
        vm.stopPrank();
        vm.startPrank(bob);
        cometWrapper.redeem(cometWrapper.maxRedeem(bob), bob, bob);
        vm.stopPrank();
    }

    function test__disallowZeroSharesOrAssets() public {
        vm.expectRevert(CometHelpers.ZeroShares.selector);
        cometWrapper.mint(0, alice);
        vm.expectRevert(CometHelpers.ZeroShares.selector);
        cometWrapper.redeem(0, alice, alice);
        vm.expectRevert(CometHelpers.ZeroAssets.selector);
        cometWrapper.withdraw(0, alice, alice);
        vm.expectRevert(CometHelpers.ZeroAssets.selector);
        cometWrapper.deposit(0, alice);
    }

    function test__revertOnNoChangeInPrincipal() public {
        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);

        // any balance changes should also change principal
        vm.expectRevert(CometHelpers.NoChangeInPrincipal.selector);
        cometWrapper.mint(1, alice);

        // any balance changes should also change principal
        vm.expectRevert(CometHelpers.NoChangeInPrincipal.selector);
        cometWrapper.deposit(1, alice);
        vm.stopPrank();
    }

    function test__transfer() public {
        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);
        cometWrapper.mint(9_000e6, alice);
        cometWrapper.transferFrom(alice, bob, 1_337e6);
        vm.stopPrank();
        assertEq(cometWrapper.balanceOf(alice), 7_663e6);
        assertEq(cometWrapper.balanceOf(bob), 1_337e6);
        assertEq(cometWrapper.totalSupply(), 9_000e6 + cometWrapper.INITIAL_MINT());

        // assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));
        skip(30 days);

        vm.startPrank(bob);
        comet.allow(wrapperAddress, true);
        cometWrapper.transfer(alice, 777e6);
        cometWrapper.transfer(alice, 111e6);
        cometWrapper.transfer(alice, 99e6);
        vm.stopPrank();

        assertEq(cometWrapper.balanceOf(alice), 7_663e6 + 777e6 + 111e6 + 99e6);
        assertEq(cometWrapper.balanceOf(bob), 1_337e6 - 777e6 - 111e6 - 99e6);
        assertEq(cometWrapper.totalSupply(), 9_000e6 + cometWrapper.INITIAL_MINT());

        skip(30 days);
        assertEq(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress));

        vm.startPrank(alice);
        cometWrapper.withdraw(cometWrapper.maxWithdraw(alice), alice, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        cometWrapper.redeem(cometWrapper.maxRedeem(bob), bob, bob);
        vm.stopPrank();

        uint256 totalAssets =
            cometWrapper.maxWithdraw(alice) + cometWrapper.maxWithdraw(bob) + cometWrapper.INITIAL_MINT();
        assertLe(totalAssets, cometWrapper.totalAssets());
    }

    function test__transferFromWorksForSender() public {
        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);
        cometWrapper.mint(5_000e6, alice);

        cometWrapper.transferFrom(alice, bob, 2_500e6);
        assertEq(cometWrapper.balanceOf(alice), 2_500e6);
        vm.stopPrank();
    }

    function test__transferFromRespectsAllowances() public {
        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);
        cometWrapper.mint(5_000e6, alice);
        vm.stopPrank();

        // Need approvals to transferFrom alice to bob
        vm.startPrank(bob);
        vm.expectRevert(CometHelpers.LackAllowance.selector);
        cometWrapper.transferFrom(alice, bob, 5_000e6);
        vm.stopPrank();

        vm.prank(alice);
        cometWrapper.approve(bob, 2_500e6);

        vm.startPrank(bob);
        // Allowances should be updated when transferFrom is done
        assertEq(cometWrapper.allowance(alice, bob), 2_500e6);
        cometWrapper.transferFrom(alice, bob, 2_500e6);
        assertEq(cometWrapper.balanceOf(alice), 2_500e6);
        assertEq(cometWrapper.balanceOf(bob), 2_500e6);

        vm.expectRevert(CometHelpers.LackAllowance.selector);
        cometWrapper.transferFrom(alice, bob, 2_500e6);
        vm.stopPrank();
        assertEq(cometWrapper.allowance(alice, bob), 0);

        // Infinite allowance does not decrease allowance
        vm.prank(bob);
        cometWrapper.approve(alice, type(uint256).max);

        vm.startPrank(alice);
        cometWrapper.transferFrom(bob, alice, 1_000e6);
        assertEq(cometWrapper.allowance(bob, alice), type(uint256).max);
        vm.stopPrank();
    }

    function test__transferFromRevertsOnLackingAllowance() public {
        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(1_000e6, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(CometHelpers.LackAllowance.selector);
        cometWrapper.transferFrom(alice, bob, 900e6);
        vm.stopPrank();

        vm.prank(alice);
        cometWrapper.approve(bob, 4_000e6);

        vm.startPrank(bob);
        vm.expectRevert();
        cometWrapper.transferFrom(alice, bob, 2_000e6);
        cometWrapper.transferFrom(alice, bob, 900e6);
        vm.expectRevert();
        cometWrapper.transferFrom(alice, bob, 3_000e6);
        assertEq(cometWrapper.balanceOf(bob), 900e6);
        vm.stopPrank();
    }

    function test__transfersWithZeroDisallowed() public {
        vm.expectRevert(CometHelpers.ZeroTransfer.selector);
        cometWrapper.transferFrom(alice, bob, 0);

        vm.expectRevert(CometHelpers.ZeroTransfer.selector);
        cometWrapper.transfer(bob, 0);
    }
}
