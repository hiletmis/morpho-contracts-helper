// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./external/api3/interfaces/IApi3ServerV1.sol";
import {IMorpho, MarketParams, Market, Id, Position} from "./external/morpho/interfaces/IMorpho.sol";
import {IERC20} from "./external/morpho/interfaces/IERC20.sol";

contract LiquidationHelper {

    IApi3ServerV1 public immutable api3ServerV1;
    IMorpho public immutable morpho;
    address public immutable owner;

    struct LiquidationParams {
        MarketParams marketParams;
        address borrower;
        uint256 seizedAssets;
        uint256 repaidShares;
        bytes   data;
    }

    constructor(address _api3ServerV1, address _morpho) {
        api3ServerV1 = IApi3ServerV1(_api3ServerV1);
        morpho     = IMorpho(_morpho);
        owner      = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    function _executeMulticall(bytes[] calldata data) internal {
        uint256 callCount = data.length;
        for (uint256 ind = 0; ind < callCount; ) {
            bool success;
            bytes memory returndata;
            
            (success, returndata) = address(api3ServerV1).call(data[ind]);
            
            if (!success) {
                if (returndata.length > 0) {
                    assembly {
                        let returndata_size := mload(returndata)
                        revert(add(32, returndata), returndata_size)
                    }
                } else {
                    revert("Multicall: No revert string");
                }
            }
            unchecked { ind++; }
        }
    }

    function multicallAndTip(bytes[] calldata data) external payable {
        require(msg.value > 0, "No tip");
        _executeMulticall(data);
        _tipBuilder(msg.value);
    }

    function _tipBuilder(uint256 amount) private {
        (bool tipped, ) = block.coinbase.call{value: amount}("");
        require(tipped, "Coinbase tip failed");
    }

    function updateAndLiquidate(
        bytes[] calldata data,
        LiquidationParams calldata liq,
        uint256 maxUSDCToUse,
        uint256 tipAmount
    ) external payable {
        IERC20 loanToken = IERC20(liq.marketParams.loanToken);
        
        uint256 balanceBefore = loanToken.balanceOf(address(this));

        loanToken.transferFrom(msg.sender, address(this), maxUSDCToUse);

        _executeMulticall(data);
        loanToken.approve(address(morpho), type(uint256).max);
        morpho.liquidate(liq.marketParams, liq.borrower, liq.seizedAssets, liq.repaidShares, liq.data);
        loanToken.approve(address(morpho), 0);

        _sweepTokens(loanToken, liq.marketParams.collateralToken, msg.sender);

        require(loanToken.balanceOf(address(this)) <= balanceBefore, "Safety check: Funds trapped!");

        uint256 finalTip = tipAmount > 0 ? tipAmount : msg.value;
        require(address(this).balance >= finalTip, "Insufficient balance for tip");
        _tipBuilder(finalTip);
    }

    function _sweepTokens(IERC20 loanToken, address collateralAddress, address recipient) private {
        uint256 remainingLoan = loanToken.balanceOf(address(this));
        if (remainingLoan > 0) {
            loanToken.transfer(recipient, remainingLoan);
        }

        IERC20 collateralToken = IERC20(collateralAddress);
        uint256 collateralEarned = collateralToken.balanceOf(address(this));
        if (collateralEarned > 0) {
            collateralToken.transfer(recipient, collateralEarned);
        }
    }

    function withdrawToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }

    function withdrawETH(uint256 amount) external onlyOwner {
        (bool ok,) = owner.call{value: amount}("");
        require(ok, "ETH withdraw failed");
    }

    receive() external payable {}
}