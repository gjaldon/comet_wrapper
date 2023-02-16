// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {CometWrapper, CometInterface, ICometRewards, CometHelpers, ERC20} from "../src/CometWrapper.sol";

contract BaseTest is Test {
    address constant cometAddress = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant rewardAddress = 0x1B0e765F6224C21223AeA2af16c1C46E38885a40;
    address constant compAddress = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address constant usdcHolder = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
    address constant usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant cusdcHolder = 0x638e9ad05DBd35B1c19dF3a4EAa0642A3B90A2AD;

    CometWrapper public cometWrapper;
    CometInterface public comet;
    ICometRewards public cometRewards;
    ERC20 public usdc;
    ERC20 public comp;
    address public wrapperAddress;

    address alice = address(0xABCD);
    address bob = address(0xDCBA);

    function setUp() public virtual {
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.createSelectFork(vm.rpcUrl("mainnet"), 16617900);

        usdc = ERC20(usdcAddress);
        comp = ERC20(compAddress);
        comet = CometInterface(cometAddress);
        cometRewards = ICometRewards(rewardAddress);
        cometWrapper = new CometWrapper(ERC20(cometAddress), ICometRewards(rewardAddress), "Wrapped Comet USDC", "WcUSDCv3");
        wrapperAddress = address(cometWrapper);
    }
}
