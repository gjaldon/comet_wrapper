// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {CometWrapper, CometInterface} from "../src/CometWrapper.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import "forge-std/console.sol";

address constant cometAddress = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
address constant usdcHolder = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
address constant usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
address constant cusdcHolder = 0x638e9ad05DBd35B1c19dF3a4EAa0642A3B90A2AD;

contract CometWrapperTest is Test {
    CometWrapper public cometWrapper;
    CometInterface public comet;
    ERC20 public usdc;

    address alice = address(0xABCD);
    address bob = address(0xDCBA);

    function setUp() public {
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.createSelectFork(vm.rpcUrl("mainnet"), 16617900);

        usdc = ERC20(usdcAddress);
        comet = CometInterface(cometAddress);
        cometWrapper = new CometWrapper(ERC20(cometAddress), "Comet USDC", "cUSDCv3");

        vm.prank(cusdcHolder);
        comet.transfer(alice, 10_000e6);
        assertGt(comet.balanceOf(alice), 999e6);

        vm.prank(cusdcHolder);
        comet.transfer(bob, 10_000e6);
        assertGt(comet.balanceOf(bob), 999e6);
    }

    function test__totalAssets() public {
        assertEq(cometWrapper.totalAssets(), 0);

        vm.startPrank(alice);
        comet.allow(address(cometWrapper), true);
        cometWrapper.deposit(5_000e6, alice);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));
        vm.warp(block.timestamp + 14 days);
        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));

        vm.startPrank(bob);
        comet.allow(address(cometWrapper), true);
        cometWrapper.deposit(5_000e6, bob);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));
        vm.warp(block.timestamp + 14 days);
        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));
    }

    function test__deposit() public {
        vm.startPrank(alice);
        comet.allow(address(cometWrapper), true);
        cometWrapper.deposit(5_000e6, alice);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));
        // Account for rounding errors that lead to difference of 1
        assertEq(cometWrapper.maxWithdraw(alice) - 1, comet.balanceOf(alice));

        vm.warp(block.timestamp + 14 days);
        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));
        // Account for rounding errors that lead to difference of 1
        assertEq(cometWrapper.maxWithdraw(alice) - 1, comet.balanceOf(alice));

        vm.startPrank(bob);
        comet.allow(address(cometWrapper), true);
        cometWrapper.deposit(7_777e6, bob);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));
        uint256 totalAssets = cometWrapper.maxWithdraw(alice) + cometWrapper.maxWithdraw(bob);
        // Alice and Bob should be able to withdraw all their assets without issue
        assertLe(totalAssets, cometWrapper.totalAssets());
    }

    function test__withdraw() public {
        vm.startPrank(alice);
        comet.allow(address(cometWrapper), true);
        cometWrapper.deposit(9_101e6, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        comet.allow(address(cometWrapper), true);
        cometWrapper.deposit(2_555e6, bob);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));

        vm.warp(block.timestamp + 14 days);
        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));

        vm.prank(alice);
        cometWrapper.withdraw(173e6, alice, alice);
        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));

        vm.warp(block.timestamp + 500 days);
        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));

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

        assertEq(cometWrapper.totalAssets(), 0);
    }

    function test__mint() public {
        vm.startPrank(alice);
        comet.allow(address(cometWrapper), true);
        cometWrapper.mint(9_000e6, alice);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));
        assertEq(cometWrapper.balanceOf(alice), 9_000e6);
        assertEq(cometWrapper.maxRedeem(alice), cometWrapper.balanceOf(alice));

        vm.startPrank(bob);
        comet.allow(address(cometWrapper), true);
        cometWrapper.mint(7_777e6, bob);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));
        assertEq(cometWrapper.balanceOf(bob), 7_777e6);
        assertEq(cometWrapper.maxRedeem(bob), cometWrapper.balanceOf(bob));

        uint256 totalAssets = cometWrapper.maxWithdraw(bob) + cometWrapper.maxWithdraw(alice);
        assertEq(totalAssets + 1, cometWrapper.totalAssets());
    }

    function test__redeem() public {
        vm.startPrank(alice);
        comet.allow(address(cometWrapper), true);
        cometWrapper.mint(9_000e6, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        comet.allow(address(cometWrapper), true);
        cometWrapper.mint(7_777e6, bob);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));

        uint256 totalRedeems = cometWrapper.maxRedeem(alice) + cometWrapper.maxRedeem(bob);
        assertEq(totalRedeems, cometWrapper.totalSupply());

        vm.warp(block.timestamp + 500 days);

        // All users can fully redeem shares
        vm.startPrank(alice);
        cometWrapper.redeem(cometWrapper.maxRedeem(alice), alice, alice);
        vm.stopPrank();
        vm.startPrank(bob);
        cometWrapper.redeem(cometWrapper.maxRedeem(bob), bob, bob);
        vm.stopPrank();
    }

    function test__transfer() public {
        vm.startPrank(alice);
        comet.allow(address(cometWrapper), true);
        cometWrapper.mint(9_000e6, alice);
        cometWrapper.transferFrom(alice, bob, 1_337e6);
        vm.stopPrank();

        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));
        vm.warp(block.timestamp + 30 days);

        vm.startPrank(bob);
        comet.allow(address(cometWrapper), true);
        cometWrapper.transfer(alice, 777e6);
        cometWrapper.transfer(alice, 111e6);
        cometWrapper.transfer(alice, 99e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);
        assertEq(cometWrapper.totalAssets(), comet.balanceOf(address(cometWrapper)));

        assertEq(cometWrapper.underlyingBalance(alice), cometWrapper.maxWithdraw(alice));

        vm.startPrank(alice);
        cometWrapper.withdraw(cometWrapper.maxWithdraw(alice), alice, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        cometWrapper.redeem(cometWrapper.maxRedeem(bob), bob, bob);
        vm.stopPrank();

        assertEq(cometWrapper.maxWithdraw(alice) + cometWrapper.maxWithdraw(bob), cometWrapper.totalAssets());
    }
}
