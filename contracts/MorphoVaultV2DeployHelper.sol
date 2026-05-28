// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// =============================================================================
//  MorphoVaultV2DeployHelper
// =============================================================================

import {IVaultV2Factory} from "./external/morpho/interfaces/IVaultV2Factory.sol";
import {IVaultV2} from "./external/morpho/interfaces/IVaultV2.sol";
import {IERC20} from "./external/morpho/interfaces/IERC20.sol";
import {IERC4626} from "./external/morpho/interfaces/IERC4626.sol";
import {IMorpho, MarketParams, Id, Position} from "./external/morpho/interfaces/IMorpho.sol";
import {IMorphoMarketV1AdapterV2} from "./external/morpho/interfaces/IMorphoMarketV1AdapterV2.sol";
import {IMorphoMarketV1AdapterV2Factory} from "./external/morpho/interfaces/IMorphoMarketV1AdapterV2Factory.sol";

contract MorphoVaultV2DeployHelper {

    address public immutable vaultV2FactoryAddress;
    address public immutable adapterV2FactoryAddress;
    address public immutable morphoRegistryAddress;

    address constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    constructor(address _vaultV2FactoryAddress, address _adapterV2FactoryAddress, address _morphoRegistryAddress) {
        vaultV2FactoryAddress = _vaultV2FactoryAddress;
        adapterV2FactoryAddress = _adapterV2FactoryAddress;
        morphoRegistryAddress = _morphoRegistryAddress;
    }

    struct DeployParams {
        address asset;
        
        string  vaultName;
        string  vaultSymbol;
        
        address finalOwner;
        address finalCurator;      
        address allocator;
        address sentinel;    

        bytes32 marketID;      
        
        uint256 vaultTimelockHigh; 
        uint256 vaultTimelockMid;  
        uint256 adapterTimelock;   
    }

    struct DeployResult {
        address vault;
        address adapter;
    }

    function _deploy(DeployParams calldata p) internal returns (DeployResult memory result) {
        bytes32 uniqueSalt = keccak256(abi.encodePacked(block.timestamp + gasleft()));

        address vault = IVaultV2Factory(vaultV2FactoryAddress).createVaultV2(
            address(this),
            p.asset,
            uniqueSalt
        );

        result.vault = vault;
        IVaultV2 iVault2 = IVaultV2(vault);

        if (bytes(p.vaultName).length > 0) {
            iVault2.setName(p.vaultName);
        }

        if (bytes(p.vaultSymbol).length > 0) {
            iVault2.setSymbol(p.vaultSymbol);
        }

        iVault2.setCurator(address(this));
        
        address adapter = IMorphoMarketV1AdapterV2Factory(adapterV2FactoryAddress).createMorphoMarketV1AdapterV2(vault);
        result.adapter = adapter;

        iVault2.submit(abi.encodeCall(IVaultV2.setIsAllocator, (p.allocator, true)));
        iVault2.submit(abi.encodeCall(IVaultV2.setIsAllocator, (address(this), true)));
        iVault2.submit(abi.encodeCall(IVaultV2.setAdapterRegistry, (morphoRegistryAddress)));
        
        bytes memory adapterIdData = abi.encode("this", adapter);
        iVault2.submit(abi.encodeCall(IVaultV2.addAdapter, (adapter)));
        iVault2.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (adapterIdData, type(uint128).max)));
        iVault2.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (adapterIdData, 1e18)));
 
        iVault2.submit(abi.encodeCall(IVaultV2.abdicate, (IVaultV2.setAdapterRegistry.selector)));
        iVault2.submit(abi.encodeCall(IVaultV2.abdicate, (IVaultV2.setReceiveSharesGate.selector)));
        iVault2.submit(abi.encodeCall(IVaultV2.abdicate, (IVaultV2.setSendSharesGate.selector)));
        iVault2.submit(abi.encodeCall(IVaultV2.abdicate, (IVaultV2.setReceiveAssetsGate.selector)));

        iVault2.setAdapterRegistry(morphoRegistryAddress);
        iVault2.setIsAllocator(p.allocator, true);
        iVault2.setIsAllocator(address(this), true);
        iVault2.addAdapter(adapter);

        iVault2.increaseAbsoluteCap(adapterIdData, type(uint128).max);
        iVault2.increaseRelativeCap(adapterIdData, 1e18);

        iVault2.abdicate(IVaultV2.setAdapterRegistry.selector);
        iVault2.abdicate(IVaultV2.setReceiveSharesGate.selector);
        iVault2.abdicate(IVaultV2.setSendSharesGate.selector);
        iVault2.abdicate(IVaultV2.setReceiveAssetsGate.selector);

        if (p.marketID != bytes32(0)) {
            _configureMarketAndLiquidityAdapter(vault, p.marketID, adapter, p.asset);
        }

        iVault2.submit(abi.encodeCall(IVaultV2.setIsAllocator, (address(this), false)));
        iVault2.setIsAllocator(address(this), false);

        _configureVaultTimelocks(vault, p.vaultTimelockHigh, p.vaultTimelockMid);
        _configureAdapterTimelocks(adapter, p.adapterTimelock);

        iVault2.setCurator(p.finalCurator);

        if (p.sentinel != address(0)) {
            iVault2.setIsSentinel(p.sentinel, true);
        }
        
        iVault2.setOwner(p.finalOwner);

        emit VaultDeployed(vault, adapter, p.finalOwner, p.finalCurator, p.allocator);
    }

    function _configureMarketAndLiquidityAdapter(address vault, bytes32 marketID, address adapter, address loanAsset) internal {
        IVaultV2 iVault2 = IVaultV2(vault);
        IMorphoMarketV1AdapterV2 iAdapter = IMorphoMarketV1AdapterV2(adapter);
        
        address morpho = iAdapter.morpho();
        
        MarketParams memory marketParams = IMorpho(morpho).idToMarketParams(Id.wrap(marketID));

        address irm = iAdapter.adaptiveCurveIrm();
        _validateMarketParams(marketParams, loanAsset, irm);

        bytes memory liquidityData = abi.encode(marketParams);
        iVault2.submit(abi.encodeCall(IVaultV2.setLiquidityAdapterAndData, (adapter, liquidityData)));
        iVault2.setLiquidityAdapterAndData(address(iAdapter), liquidityData);

        Position memory deadPosition = IMorpho(morpho).position(Id.wrap(marketID), address(DEAD_ADDRESS));
        uint256 deadSupplyShares = deadPosition.supplyShares;

        _validateDepositAmount(1e9, deadSupplyShares);

        bytes memory collateralTokenIdData = abi.encode("collateralToken", marketParams.collateralToken);
        iVault2.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (collateralTokenIdData, type(uint128).max)));
        iVault2.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (collateralTokenIdData, 1e18)));
        iVault2.increaseAbsoluteCap(collateralTokenIdData, type(uint128).max);
        iVault2.increaseRelativeCap(collateralTokenIdData, 1e18);

        bytes memory marketIdData = abi.encode("this/marketParams", address(adapter), marketParams);
        iVault2.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (marketIdData, type(uint128).max)));
        iVault2.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (marketIdData, 1e18)));
        iVault2.increaseAbsoluteCap(marketIdData, type(uint128).max);
        iVault2.increaseRelativeCap(marketIdData, 1e18);
    }

    function _validateDepositAmount(uint256 requiredDeadDeposit, uint256 deadSupplyShares) internal pure {
        require(deadSupplyShares >= requiredDeadDeposit, "Market needs dead deposit");
    }

    function _validateMarketParams(MarketParams memory marketParams, address expectedAsset, address expectedIrm)
        internal
        pure
    {
        require(marketParams.loanToken == expectedAsset, "Market loanToken does not match vault asset");
        require(marketParams.irm == expectedIrm, "Market IRM does not match adaptiveCurveIrm");
        require(marketParams.collateralToken != address(0), "Market not found (collateralToken is zero)");
    }

    function _configureVaultTimelocks(
        address vault,
        uint256 highDuration,
        uint256 midDuration
    ) internal {
        IVaultV2 iVault = IVaultV2(vault);

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = iVault.addAdapter.selector;
        selectors[1] = iVault.increaseAbsoluteCap.selector;
        selectors[2] = iVault.increaseRelativeCap.selector;
        selectors[3] = iVault.setForceDeallocatePenalty.selector;

        selectors[4] = iVault.abdicate.selector;
        selectors[5] = iVault.removeAdapter.selector;
        selectors[6] = iVault.increaseTimelock.selector; 
 
        for (uint256 i = 0; i < 4; i++) {
            iVault.submit(abi.encodeCall(IVaultV2.increaseTimelock, (selectors[i], midDuration)));
            iVault.increaseTimelock(selectors[i], midDuration);
        }

        for (uint256 i = 4; i < selectors.length; i++) {
            iVault.submit(abi.encodeCall(IVaultV2.increaseTimelock, (selectors[i], highDuration))); 
            iVault.increaseTimelock(selectors[i], highDuration);
        }

        emit VaultTimelocksConfigured(vault, highDuration, midDuration);
    }

    function _configureAdapterTimelocks(
        address adapter,
        uint256 duration
    ) internal {
        IMorphoMarketV1AdapterV2 iAdapter = IMorphoMarketV1AdapterV2(adapter);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = IMorphoMarketV1AdapterV2.abdicate.selector;
        selectors[1] = IMorphoMarketV1AdapterV2.setSkimRecipient.selector;
        selectors[2] = IMorphoMarketV1AdapterV2.burnShares.selector;
        selectors[3] = IMorphoMarketV1AdapterV2.increaseTimelock.selector; 

        for (uint256 i = 0; i < selectors.length; i++) {
            iAdapter.submit(abi.encodeCall(IMorphoMarketV1AdapterV2.increaseTimelock, (selectors[i], duration)));
            iAdapter.increaseTimelock(selectors[i], duration);
        }

        emit AdapterTimelocksConfigured(adapter, duration);
    }

    function deploy(DeployParams calldata p) external returns (DeployResult memory result) {
        result = _deploy(p);
    }
        
    event VaultDeployed(
        address indexed vault,
        address indexed adapter,
        address finalOwner,
        address finalCurator,
        address allocator
    );

    event VaultTimelocksConfigured(
        address indexed vault,
        uint256 highDuration,
        uint256 midDuration
    );

    event AdapterTimelocksConfigured(
        address indexed adapter,
        uint256 duration
    );
}
