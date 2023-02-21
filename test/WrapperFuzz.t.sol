pragma solidity ^0.8.13;

import "../src/CometWrapper.sol";
import "../src/vendor/CometInterface.sol";
import "../src/vendor/ICometRewards.sol";
// import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./DSTestPlus.sol";
import "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import "../lib/forge-std/src/console.sol";

contract WrapperFuzzTest is DSTestPlus {
    address constant public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    ERC20 constant public CUSDC_V3 = ERC20(0xc3d688B66703497DAA19211EEdff47f25384cdc3);
    address constant public COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    ICometRewards constant public REWARDS = ICometRewards(0x1B0e765F6224C21223AeA2af16c1C46E38885a40);
    CometWrapper public wrapper;
    CometInterface public comet = CometInterface(address(CUSDC_V3));
    uint256 public nRuns;
    address[] public users;
    uint256 public nUsers;
    uint256 public modulo;
    uint256 public rando;

    function setUp() external {
        wrapper = new CometWrapper(CUSDC_V3, REWARDS, "Wrapped cUSDCv3", "wcUSDCv3");
        rando = 58973458937458395739;
        modulo = 50000e6;
        nRuns = 100;
        nUsers = 10;
        for (uint256 i = 1; i <= nUsers; i++) {
            users.push(address(uint160(i)));
            _mintCusdc(address(uint160(i)), modulo * 100);
        }
    }

    function testDepositWithdraw() external {
        uint256 r = uint256(keccak256(abi.encodePacked(rando))) % modulo;

        // fire a bunch of random deposits and withdraws
        for (uint256 i = 0; i < nRuns; i++) {
            console.log("deposit/withdraw", i);
            for (uint256 j = 0; j < nUsers; j++) {
                uint256 currentBal = wrapper.underlyingBalance(users[j]);
                if (currentBal == 0 || r % 2 == 0) {
                    uint256 cusdcBal = CUSDC_V3.balanceOf(users[j]);
                    hevm.prank(users[j]);
                    wrapper.deposit(Math.min(cusdcBal, r), users[j]);
                } else {
                    hevm.prank(users[j]);
                    wrapper.withdraw(Math.min(currentBal, r), users[j], users[j]);
                }
                r = uint256(keccak256(abi.encodePacked(r * rando))) % modulo;
            }
        }
        _checkBalances();

        // draw down all users balances to 0
        for (uint256 k = 0; k < nUsers; k++) {
            uint256 balBefore = wrapper.underlyingBalance(users[k]);
            hevm.prank(users[k]);
            wrapper.withdraw(balBefore, users[k], users[k]);
            uint256 balAfter = wrapper.underlyingBalance(users[k]);
            // console.log("do withdraw", balBefore, balAfter);
        }
        _checkBalances();
    }

    function _mintCusdc(address user, uint256 amt) internal {
        deal(USDC, user, amt);
        hevm.startPrank(user);
        ERC20(USDC).approve(address(CUSDC_V3), amt);
        comet.allow(address(wrapper), true);
        comet.supply(USDC, amt);
        hevm.stopPrank();
    }

    function _checkBalances() internal view {
        uint256 totalUBal = 0;
        for (uint256 i = 0; i < nUsers; i++) {
            uint256 uBal = wrapper.underlyingBalance(users[i]);
            totalUBal += uBal;
        }
        uint256 wrapperBal = comet.balanceOf(address(wrapper));
        console.log("totalUBal", totalUBal);
        console.log("wrapperBal", wrapperBal);
        console.log("==", totalUBal == wrapperBal);
        if (totalUBal > wrapperBal) {
            console.log("users win", totalUBal - wrapperBal);
        } else if (wrapperBal >= totalUBal) {
            console.log("wrapper win", wrapperBal - totalUBal);
        } else {
            console.log("EQUAL");
        }
    }
}

/*
Logs:

    CONFIG:
    
    rando = 58973458937458395739;
    modulo = 50000e6;
    nRuns = 10000;
    nUsers = 50;




    RESULTS:

    totalUBal 102290372265267
    wrapperBal 102290372265165
    == false
    users win 102

    totalUBal 199
    wrapperBal 74
    == false
    users win 125
    
*/
