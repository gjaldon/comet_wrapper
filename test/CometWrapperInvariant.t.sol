// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {BaseTest, CometHelpers, CometWrapper, ERC20, ICometRewards} from "./BaseTest.sol";

contract CometWrapperInvariantTest is BaseTest {
    // Invariants:
    // - totalAssets must always be <= comet.balanceOf(address(cometWrapper))
    // - sum of all underlyingBalances of accounts <= totalAssets
    // - sum of principal of all users == underlyingPrincipal
    function test__contractBalanceInvariants(uint256 amount1, uint256 amount2) public {
        vm.assume(amount1 <= 2**48);
        vm.assume(amount2 <= 2**48);
        vm.assume(amount1 + amount2 < comet.balanceOf(cusdcHolder));
        vm.assume(amount1 > 1000e6 && amount2 > 1000e6);

        vm.prank(cusdcHolder);
        comet.transfer(alice, amount1);
        vm.prank(cusdcHolder);
        comet.transfer(bob, amount2);

        uint256 aliceBalance = comet.balanceOf(alice);
        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(aliceBalance/5, alice);
        vm.stopPrank();
        assertEq(comet.balanceOf(address(cometWrapper)), cometWrapper.totalAssets());

        uint256 bobBalance = comet.balanceOf(bob);
        vm.startPrank(bob);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(bobBalance/5, bob);
        vm.stopPrank();
        assertEq(comet.balanceOf(address(cometWrapper)), cometWrapper.totalAssets());

        skip(10000 days);

        vm.startPrank(bob);
        cometWrapper.mint(bobBalance/3, bob);
        vm.stopPrank();
        assertEq(comet.balanceOf(address(cometWrapper)), cometWrapper.totalAssets());

        vm.startPrank(alice);
        cometWrapper.mint(aliceBalance/3, alice);
        vm.stopPrank();
        assertEq(comet.balanceOf(address(cometWrapper)), cometWrapper.totalAssets());

        assertEq(cometWrapper.userPrincipal(alice) + cometWrapper.userPrincipal(bob), uint104(comet.userBasic(address(cometWrapper)).principal));

        vm.startPrank(alice);
        cometWrapper.redeem(cometWrapper.maxRedeem(alice), alice, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        cometWrapper.redeem(cometWrapper.maxRedeem(bob), bob, bob);
        vm.stopPrank();
    }

    // Invariants:
    // - transfers must not change totalSupply
    // - transfers must not change totalAssets
    function test__transferInvariants(uint256 amount1, uint256 amount2) public {
        vm.assume(amount1 <= 2**48);
        vm.assume(amount2 <= 2**48);
        vm.assume(amount1 + amount2 < comet.balanceOf(cusdcHolder));
        vm.assume(amount1 > 1000e6 && amount2 > 1000e6);

        vm.prank(cusdcHolder);
        comet.transfer(alice, amount1);
        vm.prank(cusdcHolder);
        comet.transfer(bob, amount2);

        vm.startPrank(alice);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(comet.balanceOf(alice), alice);
        vm.stopPrank();

        vm.startPrank(bob);
        comet.allow(wrapperAddress, true);
        cometWrapper.deposit(comet.balanceOf(bob), bob);
        vm.stopPrank();

        uint256 totalAssets = cometWrapper.totalAssets();
        uint256 totalSupply = cometWrapper.totalSupply();
        assertEq(totalAssets, comet.balanceOf(address(cometWrapper)));

        for (uint256 i; i < 5; i++) {
            vm.startPrank(alice);
            cometWrapper.transferFrom(alice, bob, cometWrapper.balanceOf(alice)/5);
            assertEq(cometWrapper.totalAssets(), totalAssets);
            assertEq(cometWrapper.totalSupply(), totalSupply);
            vm.stopPrank();

            vm.startPrank(bob);
            cometWrapper.transferFrom(bob, alice, cometWrapper.balanceOf(bob)/5);
            assertEq(cometWrapper.totalAssets(), totalAssets);
            assertEq(cometWrapper.totalSupply(), totalSupply);
            vm.stopPrank();

            vm.startPrank(bob);
            cometWrapper.transferFrom(bob, alice, cometWrapper.balanceOf(bob)/5);
            assertEq(cometWrapper.totalAssets(), totalAssets);
            assertEq(cometWrapper.totalSupply(), totalSupply);
            vm.stopPrank();

            vm.startPrank(alice);
            cometWrapper.transferFrom(alice, bob, cometWrapper.balanceOf(alice)/5);
            assertEq(cometWrapper.totalAssets(), totalAssets);
            assertEq(cometWrapper.totalSupply(), totalSupply);
            vm.stopPrank();
        }
    }
}