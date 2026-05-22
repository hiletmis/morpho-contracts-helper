// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct MarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
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
    }

    struct MarketData {
        TokenInfo loanToken;
        TokenInfo collateralToken;
        OracleInfo oracle;
        uint256 deadAddressSupply;
    }

    function getMarketDetailsById(bytes32 marketId) external view returns (MarketData memory) {
        MarketParams memory params = IMorpho(morphoAddress).idToMarketParams(marketId);
        
        return this.getMarketDetails(
            params.loanToken,
            params.collateralToken,
            params.oracle,
            marketId,
            msg.sender
        );
    }

    function getMarketDetails(
        address loanToken,
        address collateralToken,
        address oracle,
        bytes32 marketId,
        address connectedAddress
    ) external view returns (MarketData memory data) {
        
        data.loanToken.tokenAddress = loanToken;
        try IERC20Metadata(loanToken).name() returns (string memory _name) { data.loanToken.name = _name; } catch {}
        try IERC20Metadata(loanToken).symbol() returns (string memory _sym) { data.loanToken.symbol = _sym; } catch {}
        try IERC20Metadata(loanToken).decimals() returns (uint8 _dec) { data.loanToken.decimals = _dec; } catch {}
        
        if (connectedAddress != address(0) && morphoAddress != address(0)) {
            try IERC20Metadata(loanToken).allowance(connectedAddress, morphoAddress) returns (uint256 _allow) { data.loanToken.userAllowance = _allow; } catch {}
        }

        data.collateralToken.tokenAddress = collateralToken;
        try IERC20Metadata(collateralToken).name() returns (string memory _name) { data.collateralToken.name = _name; } catch {}
        try IERC20Metadata(collateralToken).symbol() returns (string memory _sym) { data.collateralToken.symbol = _sym; } catch {}
        try IERC20Metadata(collateralToken).decimals() returns (uint8 _dec) { data.collateralToken.decimals = _dec; } catch {}

        if (oracle != address(0)) {
            data.oracle.oracleAddress = oracle;
            try IMorphoChainlinkOracleV2(oracle).BASE_FEED_1() returns (address a) { data.oracle.baseFeed1 = a; } catch {}
            try IMorphoChainlinkOracleV2(oracle).BASE_FEED_2() returns (address a) { data.oracle.baseFeed2 = a; } catch {}
            try IMorphoChainlinkOracleV2(oracle).BASE_VAULT() returns (address a) { data.oracle.baseVault = a; } catch {}
            try IMorphoChainlinkOracleV2(oracle).BASE_VAULT_CONVERSION_SAMPLE() returns (address a) { data.oracle.baseVaultConversionSample = a; } catch {}
            try IMorphoChainlinkOracleV2(oracle).QUOTE_FEED_1() returns (address a) { data.oracle.quoteFeed1 = a; } catch {}
            try IMorphoChainlinkOracleV2(oracle).QUOTE_FEED_2() returns (address a) { data.oracle.quoteFeed2 = a; } catch {}
            try IMorphoChainlinkOracleV2(oracle).QUOTE_VAULT() returns (address a) { data.oracle.quoteVault = a; } catch {}
            try IMorphoChainlinkOracleV2(oracle).QUOTE_VAULT_CONVERSION_SAMPLE() returns (address a) { data.oracle.quoteVaultConversionSample = a; } catch {}
            try IMorphoChainlinkOracleV2(oracle).SCALE_FACTOR() returns (uint256 s) { data.oracle.scaleFactor = s; } catch {}
            try IMorphoChainlinkOracleV2(oracle).price() returns (uint256 p) { data.oracle.currentPrice = p; } catch {}
        }

        if (morphoAddress != address(0) && marketId != bytes32(0)) {
            address deadAddress = 0x000000000000000000000000000000000000dEaD;
            try IMorpho(morphoAddress).position(marketId, deadAddress) returns (uint128 supplyShares, uint128, uint128) {
                data.deadAddressSupply = uint256(supplyShares);
            } catch {}
        }
    }
}