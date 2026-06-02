// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {AggregatorV3Interface} from "./external/morpho/interfaces/AggregatorV3Interface.sol";
import {IMorpho, MarketParams, Market,  Id, Position} from "./external/morpho/interfaces/IMorpho.sol";
import {IMorphoChainlinkOracleV2} from "./external/morpho/interfaces/IMorphoChainlinkOracleV2.sol";
import {IERC4626} from "./external/morpho/interfaces/IERC4626.sol";

contract MorphoMarketDataFetcher {

    address public immutable morphoAddress;

    constructor(address _morphoAddress) {
        morphoAddress = _morphoAddress;
    }

    struct TokenInfo {
        address tokenAddress;
        string name;
        string symbol;
        uint8 decimals;
        uint256 userAllowance;
    }

    struct MockOracleInfo {
        address oracleAddress;
        uint256 price;
        string symbol;
        uint8 decimals;
    }

    struct OracleInfo {
        address oracleAddress;
        AggregatorV3Interface baseFeed1;
        AggregatorV3Interface baseFeed2;
        IERC4626 baseVault;
        uint256 baseVaultConversionSample;
        AggregatorV3Interface quoteFeed1;
        AggregatorV3Interface quoteFeed2;
        IERC4626 quoteVault;
        uint256 quoteVaultConversionSample;
        uint256 scaleFactor;
        uint256 currentPrice;
        MockOracleInfo baseFeed;
        MockOracleInfo quoteFeed;
    }

    struct MarketData {
        TokenInfo loanToken;
        TokenInfo collateralToken;
        OracleInfo oracle;
        MarketParams marketParams;
        uint256 deadAddressSupply;
    }

    function getMarketDetails(
        bytes32 marketId,
        address user
    ) external view returns (MarketData memory data) {

        MarketParams memory params = IMorpho(morphoAddress).idToMarketParams(Id.wrap(marketId));
        
        data.marketParams = params;
        
        data.loanToken.tokenAddress = params.loanToken;
        try IERC20Metadata(params.loanToken).name() returns (string memory _name) { data.loanToken.name = _name; } catch {}
        try IERC20Metadata(params.loanToken).symbol() returns (string memory _sym) { data.loanToken.symbol = _sym; } catch {}
        try IERC20Metadata(params.loanToken).decimals() returns (uint8 _dec) { data.loanToken.decimals = _dec; } catch {}
        
        if (user != address(0) && morphoAddress != address(0)) {
            try IERC20Metadata(params.loanToken).allowance(user, morphoAddress) returns (uint256 _allow) { 
                data.loanToken.userAllowance = _allow; 
            } catch {}
        }

        data.collateralToken.tokenAddress = params.collateralToken;
        try IERC20Metadata(params.collateralToken).name() returns (string memory _name) { data.collateralToken.name = _name; } catch {}
        try IERC20Metadata(params.collateralToken).symbol() returns (string memory _sym) { data.collateralToken.symbol = _sym; } catch {}
        try IERC20Metadata(params.collateralToken).decimals() returns (uint8 _dec) { data.collateralToken.decimals = _dec; } catch {}

        if (params.oracle != address(0)) {
            data.oracle.oracleAddress = params.oracle;
            try IMorphoChainlinkOracleV2(params.oracle).BASE_FEED_1() returns (AggregatorV3Interface a) { data.oracle.baseFeed1 = a; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).BASE_FEED_2() returns (AggregatorV3Interface a) { data.oracle.baseFeed2 = a; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).BASE_VAULT() returns (IERC4626 a) { data.oracle.baseVault = a; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).BASE_VAULT_CONVERSION_SAMPLE() returns (uint256 a) { data.oracle.baseVaultConversionSample = a; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).QUOTE_FEED_1() returns (AggregatorV3Interface a) { data.oracle.quoteFeed1 = a; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).QUOTE_FEED_2() returns (AggregatorV3Interface a) { data.oracle.quoteFeed2 = a; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).QUOTE_VAULT() returns (IERC4626 a) { data.oracle.quoteVault = a; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).QUOTE_VAULT_CONVERSION_SAMPLE() returns (uint256 a) { data.oracle.quoteVaultConversionSample = a; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).SCALE_FACTOR() returns (uint256 s) { data.oracle.scaleFactor = s; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).price() returns (uint256 p) { data.oracle.currentPrice = p; } catch {}
        }
        
        if (address(data.oracle.baseFeed1) != address(0)) {
            data.oracle.baseFeed.oracleAddress = address(data.oracle.baseFeed1);
            
            try data.oracle.baseFeed1.latestRoundData() returns (
                uint80, int256 answer, uint256, uint256, uint80
            ) { 
                data.oracle.baseFeed.price = answer > 0 ? uint256(answer) : 0; 
            } catch {}

            try data.oracle.baseFeed1.decimals() returns (uint8 _dec) { data.oracle.baseFeed.decimals = _dec; } catch {}
            try data.oracle.baseFeed1.description() returns (string memory _sym) { data.oracle.baseFeed.symbol = _sym; } catch {}
        }

        if (address(data.oracle.quoteFeed1) != address(0)) {
            data.oracle.quoteFeed.oracleAddress = address(data.oracle.quoteFeed1);
            
            try data.oracle.quoteFeed1.latestRoundData() returns (
                uint80, int256 answer, uint256, uint256, uint80
            ) { 
                data.oracle.quoteFeed.price = answer > 0 ? uint256(answer) : 0; 
            } catch {}

            try data.oracle.quoteFeed1.decimals() returns (uint8 _dec) { data.oracle.quoteFeed.decimals = _dec; } catch {}
            try data.oracle.quoteFeed1.description() returns (string memory _sym) { data.oracle.quoteFeed.symbol = _sym; } catch {}
        }

        if (morphoAddress != address(0) && marketId != bytes32(0)) {
            address deadAddress = 0x000000000000000000000000000000000000dEaD;

            Position memory deadPosition = IMorpho(morphoAddress).position(Id.wrap(marketId), deadAddress);
            data.deadAddressSupply = deadPosition.supplyShares;
        }
    }
}