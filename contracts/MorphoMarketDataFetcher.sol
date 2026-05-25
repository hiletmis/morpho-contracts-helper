// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct MarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}

interface IChainlinkAggregator {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

interface IERC20Metadata {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IMorphoChainlinkOracleV2 {
    function BASE_FEED_1() external view returns (address);
    function BASE_FEED_2() external view returns (address);
    function BASE_VAULT() external view returns (address);
    function BASE_VAULT_CONVERSION_SAMPLE() external view returns (address);
    function QUOTE_FEED_1() external view returns (address);
    function QUOTE_FEED_2() external view returns (address);
    function QUOTE_VAULT() external view returns (address);
    function QUOTE_VAULT_CONVERSION_SAMPLE() external view returns (address);
    function SCALE_FACTOR() external view returns (uint256);
    function price() external view returns (uint256);
}

interface IMorpho {
    function position(bytes32 marketId, address account) external view returns (uint128 supplyShares, uint128 borrowShares, uint128 collateral);
    function idToMarketParams(bytes32 marketId) external view returns (MarketParams memory);
}

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
        address baseFeed1;
        address baseFeed2;
        address baseVault;
        address baseVaultConversionSample;
        address quoteFeed1;
        address quoteFeed2;
        address quoteVault;
        address quoteVaultConversionSample;
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

        MarketParams memory params = IMorpho(morphoAddress).idToMarketParams(marketId);
        
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
            try IMorphoChainlinkOracleV2(params.oracle).BASE_FEED_1() returns (address a) { data.oracle.baseFeed1 = a; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).BASE_FEED_2() returns (address a) { data.oracle.baseFeed2 = a; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).BASE_VAULT() returns (address a) { data.oracle.baseVault = a; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).BASE_VAULT_CONVERSION_SAMPLE() returns (address a) { data.oracle.baseVaultConversionSample = a; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).QUOTE_FEED_1() returns (address a) { data.oracle.quoteFeed1 = a; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).QUOTE_FEED_2() returns (address a) { data.oracle.quoteFeed2 = a; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).QUOTE_VAULT() returns (address a) { data.oracle.quoteVault = a; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).QUOTE_VAULT_CONVERSION_SAMPLE() returns (address a) { data.oracle.quoteVaultConversionSample = a; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).SCALE_FACTOR() returns (uint256 s) { data.oracle.scaleFactor = s; } catch {}
            try IMorphoChainlinkOracleV2(params.oracle).price() returns (uint256 p) { data.oracle.currentPrice = p; } catch {}
        }
        
        if (data.oracle.baseFeed1 != address(0)) {
            data.oracle.baseFeed.oracleAddress = data.oracle.baseFeed1;
            
            try IChainlinkAggregator(data.oracle.baseFeed1).latestRoundData() returns (
                uint80, int256 answer, uint256, uint256, uint80
            ) { 
                data.oracle.baseFeed.price = answer > 0 ? uint256(answer) : 0; 
            } catch {}

            try IChainlinkAggregator(data.oracle.baseFeed1).decimals() returns (uint8 _dec) { data.oracle.baseFeed.decimals = _dec; } catch {}
            try IERC20Metadata(data.oracle.baseFeed1).symbol() returns (string memory _sym) { data.oracle.baseFeed.symbol = _sym; } catch {}
        }

        if (data.oracle.quoteFeed1 != address(0)) {
            data.oracle.quoteFeed.oracleAddress = data.oracle.quoteFeed1;
            
            try IChainlinkAggregator(data.oracle.quoteFeed1).latestRoundData() returns (
                uint80, int256 answer, uint256, uint256, uint80
            ) { 
                data.oracle.quoteFeed.price = answer > 0 ? uint256(answer) : 0; 
            } catch {}

            try IChainlinkAggregator(data.oracle.quoteFeed1).decimals() returns (uint8 _dec) { data.oracle.quoteFeed.decimals = _dec; } catch {}
            try IERC20Metadata(data.oracle.quoteFeed1).symbol() returns (string memory _sym) { data.oracle.quoteFeed.symbol = _sym; } catch {}
        }

        if (morphoAddress != address(0) && marketId != bytes32(0)) {
            address deadAddress = 0x000000000000000000000000000000000000dEaD;
            try IMorpho(morphoAddress).position(marketId, deadAddress) returns (uint128 supplyShares, uint128, uint128) {
                data.deadAddressSupply = uint256(supplyShares);
            } catch {}
        }
    }
}