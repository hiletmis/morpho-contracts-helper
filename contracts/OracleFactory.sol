// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "./external/morpho/interfaces/AggregatorV3Interface.sol";


/**
 * @title ManualChainlinkMockFeed
 * @notice Mock Chainlink feed with manual price updates and automated simulation modes.
 *
 * SIMULATION MODES:
 * ─────────────────────────────────────────────────────────────────────
 *  0 = MANUAL            → Price is manually updated via setPrice()
 *  1 = TRENDING_UP       → Price compounds by `basisPoints` every 5 minutes (STEP)
 *  2 = TRENDING_DOWN     → Price compounds down by `basisPoints` every 5 minutes (STEP)
 *  3 = CRASH_AND_RECOVER → Hourly-based custom curve:
 *        [0h – 23h)  : Gradual compound growth (+basisPoints per hour)
 *        [23h – 24h) : Sharp linear crash down to 75% of the initial base price
 *        [24h – 25h) : Linear recovery from the crashed price back to the initial base price
 *        ≥ 25h       : Remains flat at the initial base price
 * ─────────────────────────────────────────────────────────────────────
 *
 * simStartTime: Timestamp of t=0 for the simulation (automatically set on setMode() or deployment)
 * basisPoints : Rate of change (1 bp = 0.01%, e.g., 50 = 0.5% per STEP/HOUR)
 */
contract ManualChainlinkMockFeed is AggregatorV3Interface {

    // ── Enums & Constants ────────────────────────────────────────────
    uint8 public constant MODE_MANUAL           = 0;
    uint8 public constant MODE_TRENDING_UP      = 1;
    uint8 public constant MODE_TRENDING_DOWN    = 2;
    uint8 public constant MODE_CRASH_AND_RECOVER = 3;

    uint256 private constant STEP = 300; // 5 minutes step for trending modes
    uint256 private constant HOUR = 3600; // 1 hour step for crash & recover mode
    uint256 private constant BPS_DENOM = 10_000;

    // ── Storage ──────────────────────────────────────────────────────
    mapping(address => bool) public isOwner;

    int256  private _price;
    uint8   private immutable _decimals;
    string public description;

    uint8   public  simMode;
    uint256 public  simStartTime;
    uint256 public  basisPoints;

    // ── Events ───────────────────────────────────────────────────────
    event PriceUpdated(int256 newPrice, address indexed updatedBy);
    event ModeChanged(uint8 newMode, uint256 startTime, uint256 basisPoints);
    event OwnerAdded(address indexed newOwner);

    // ── Modifiers ────────────────────────────────────────────────────
    modifier onlyOwner() {
        require(isOwner[msg.sender], "Unauthorized");
        _;
    }

    // ── Constructor ──────────────────────────────────────────────────
    constructor(
        int256 initialPrice,
        uint8  decimals_,
        string memory description_,
        address[] memory owners_,
        uint8 simMode_
    ) {
        require(owners_.length > 0, "No owners provided");
        for (uint256 i = 0; i < owners_.length; i++) {
            require(owners_[i] != address(0), "Zero address");
            isOwner[owners_[i]] = true;
            emit OwnerAdded(owners_[i]);
        }
        _price      = initialPrice;
        _decimals   = decimals_;
        description = description_;
        simMode     = simMode_;
        basisPoints = 50; // default: 0.5%

        if (simMode_ != MODE_MANUAL) {
            simStartTime = block.timestamp;
        }
    }

    // ── IChainlinkAggregator ─────────────────────────────────────────

    function latestRoundData()
        external
        view
        override
        returns (
            uint80  roundId,
            int256  answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80  answeredInRound
        )
    {
        answer = _computePrice();
        
        // Default roundId for MANUAL mode
        uint256 dynamicRoundId = 1; 
        
        // For simulation modes, generate a realistic incrementing roundId
        if (simMode != MODE_MANUAL) {
            uint256 elapsed = block.timestamp - simStartTime;
            uint256 currentStep = (simMode == MODE_CRASH_AND_RECOVER) ? HOUR : STEP;
            dynamicRoundId = (elapsed / currentStep) + 1; 
        }

        // Explicitly cast uint256 to uint80 to prevent compilation errors
        uint80 castedRoundId = uint80(dynamicRoundId);

        return (
            castedRoundId, 
            answer, 
            block.timestamp, 
            block.timestamp, 
            castedRoundId
        );
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    // ── Price Computation ────────────────────────────────────────────

    /**
     * @dev Dynamically computes the current price based on the active simulation mode.
     *      All calculations happen inside this view function without modifying the state.
     */
    function _computePrice() internal view returns (int256) {
        if (simMode == MODE_MANUAL) {
            return _price;
        }

        int256  base = _price;
        uint256 elapsed = block.timestamp - simStartTime;

        if (simMode == MODE_TRENDING_UP) {
            // compound: base * (1 + bp/10000)^steps (every 5 mins)
            uint256 stepsElapsed = elapsed / STEP;
            return _compoundGrow(base, basisPoints, stepsElapsed);
        }

        if (simMode == MODE_TRENDING_DOWN) {
            // compound: base * (1 - bp/10000)^steps (every 5 mins)
            uint256 stepsElapsed = elapsed / STEP;
            return _compoundDecay(base, basisPoints, stepsElapsed);
        }

        if (simMode == MODE_CRASH_AND_RECOVER) {
            return _crashAndRecover(base, elapsed);
        }

        return base;
    }

    /**
     * @dev CRASH_AND_RECOVER price curve (Hourly based):
     *
     * Phase A  [0 – 23h)   : Compound growth (+basisPoints per hour)
     * Phase B  [23h – 24h) : Starts at Phase A peak, linear drop to base * 0.75 within 1 hour
     * Phase C  [24h – 25h) : Linear recovery from base * 0.75 back to the original base price
     * Phase D  ≥ 25h       : Stays flat at the original base price
     */
    function _crashAndRecover(int256 base, uint256 elapsed)
        internal
        view
        returns (int256)
    {
        if (base == 0) return 0;

        uint256 PHASE_A_END = 23 * HOUR;
        uint256 PHASE_B_END = 24 * HOUR;
        uint256 PHASE_C_END = 25 * HOUR;

        // Peak price calculation strictly uses 23 hourly intervals
        int256 peakPrice = _compoundGrow(base, basisPoints, 23);
        int256 crashPrice = (base * 75) / 100;

        if (elapsed < PHASE_A_END) {
            uint256 h = elapsed / HOUR;
            return _compoundGrow(base, basisPoints, h);
        }

        if (elapsed < PHASE_B_END) {
            uint256 phaseElapsed = elapsed - PHASE_A_END;
            return _lerp(peakPrice, crashPrice, phaseElapsed, HOUR);
        }

        if (elapsed < PHASE_C_END) {
            uint256 phaseElapsed = elapsed - PHASE_B_END;
            return _lerp(crashPrice, base, phaseElapsed, HOUR);
        }

        return base;
    }

    // ── Math Helpers ─────────────────────────────────────────────────

    /**
     * @dev Integer linear interpolation:
     *      result = from + (to - from) * t / duration
     */
    function _lerp(
        int256  from,
        int256  to,
        uint256 t,
        uint256 duration
    ) internal pure returns (int256) {
        if (t >= duration) return to;
        int256 delta = to - from;
        return from + (delta * int256(t)) / int256(duration);
    }

    /**
     * @dev Compound Growth: value * ((10000 + bp) / 10000)^n
     *      Iterative approach used to manage precision and avoid overflow.
     */
    function _compoundGrow(
        int256  value,
        uint256 bp,
        uint256 n
    ) internal pure returns (int256) {
        if (n == 0 || value == 0) return value;
        
        uint256 baseRate = BPS_DENOM + bp;
        uint256 multiplier = BPS_DENOM;
        
        // Exponentiation by squaring
        while (n > 0) {
            if (n % 2 == 1) {
                multiplier = (multiplier * baseRate) / BPS_DENOM;
            }
            baseRate = (baseRate * baseRate) / BPS_DENOM;
            n /= 2;
        }
        
        return (value * int256(multiplier)) / int256(BPS_DENOM);
    }

    /**
     * @dev Compound Decay: value * ((10000 - bp) / 10000)^n
     */
    function _compoundDecay(
        int256  value,
        uint256 bp,
        uint256 n
    ) internal pure returns (int256) {
        if (n == 0 || value == 0) return value;
        
        uint256 baseRate = BPS_DENOM - bp;
        uint256 multiplier = BPS_DENOM;
        
        while (n > 0) {
            if (n % 2 == 1) {
                multiplier = (multiplier * baseRate) / BPS_DENOM;
            }
            baseRate = (baseRate * baseRate) / BPS_DENOM;
            n /= 2;
        }
        
        return (value * int256(multiplier)) / int256(BPS_DENOM);
    }

    // ── Owner Functions ──────────────────────────────────────────────

    /**
     * @notice Updates the simulation mode and resets the timer to current timestamp.
     * @param mode_        New mode (0-3)
     * @param basisPoints_ Rate of change (bp). Ignored in MANUAL mode.
     */
    function setMode(uint8 mode_, uint256 basisPoints_) external onlyOwner {
        require(mode_ <= MODE_CRASH_AND_RECOVER, "Invalid mode");
        simMode     = mode_;
        simStartTime = block.timestamp;
        basisPoints = basisPoints_;
        emit ModeChanged(mode_, block.timestamp, basisPoints_);
    }

    /**
     * @notice Updates the static price. Only allowed in MANUAL mode.
     */
    function setPrice(int256 newPrice) external onlyOwner {
        require(simMode == MODE_MANUAL, "Not in MANUAL mode");
        _price = newPrice;
        emit PriceUpdated(newPrice, msg.sender);
    }

    /**
     * @notice Updates the initial base price for automated simulation modes without resetting the timer.
     */
    function setBasePrice(int256 newBasePrice) external onlyOwner {
        _price = newBasePrice;
        
        if (simMode != MODE_MANUAL) {
            simStartTime = block.timestamp;
        }
        
        emit PriceUpdated(newBasePrice, msg.sender);
    }

    /**
     * @notice Restarts the simulation from the current timestamp (mode remains unchanged).
     */
    function restartSimulation() external onlyOwner {
        require(simMode != MODE_MANUAL, "Use setPrice for MANUAL mode");
        simStartTime = block.timestamp;
        emit ModeChanged(simMode, block.timestamp, basisPoints);
    }

    function addOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        isOwner[newOwner] = true;
        emit OwnerAdded(newOwner);
    }

    // ── View Helpers ─────────────────────────────────────────────────

    /// @notice Returns the dynamically computed current price (matches latestRoundData().answer)
    function currentPrice() external view returns (int256) {
        return _computePrice();
    }

    /// @notice Returns the seconds elapsed since the start of the current simulation
    function elapsedSeconds() external view returns (uint256) {
        if (simMode == MODE_MANUAL) return 0;
        return block.timestamp - simStartTime;
    }

    function version() external pure returns (uint256) {
        return 1; 
    }

    function getRoundData(uint80 _roundId)
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return (_roundId, _price, block.timestamp, block.timestamp, 1);
    }
}

// ─────────────────────────────────────────────────────────────────────────────

/**
 * @title ManualChainlinkMockFeedFactory
 */
contract ManualChainlinkMockFeedFactory {

    event FeedCreated(
        address indexed feed,
        string  description,
        int256  initialPrice,
        uint8   decimals,
        address[] owners
    );

    function createFeed(
        int256  initialPrice,
        uint8   decimals_,
        string memory description_,
        address[] memory owners_,
        uint8 simMode_
    ) external returns (address feedAddress) {
        require(simMode_ < 4, "Please enter a valid simulation mode. Enter 0 for manual.");

        ManualChainlinkMockFeed feed = new ManualChainlinkMockFeed(
            initialPrice,
            decimals_,
            description_,
            owners_,
            simMode_
        );
        feedAddress = address(feed);
        emit FeedCreated(feedAddress, description_, initialPrice, decimals_, owners_);
    }
}