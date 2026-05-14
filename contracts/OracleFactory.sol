// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

/**
 * @title ManualChainlinkMockFeed
 * @notice Mock Chainlink feed with manual price updates
 */
contract ManualChainlinkMockFeed is IChainlinkAggregator {
    mapping(address => bool) public isOwner;

    int256 private _price;
    uint8 private immutable _decimals;

    string public symbol;

    event PriceUpdated(int256 newPrice, address indexed updatedBy);
    event OwnerAdded(address indexed newOwner);

    modifier onlyOwner() {
        require(isOwner[msg.sender], "Unauthorized");
        _;
    }

    constructor(
        int256 initialPrice,
        uint8 decimals_,
        string memory symbol_,
        address[] memory owners_
    ) {
        require(owners_.length > 0, "No owners provided");

        for (uint256 i = 0; i < owners_.length; i++) {
            require(owners_[i] != address(0), "Zero address");

            isOwner[owners_[i]] = true;

            emit OwnerAdded(owners_[i]);
        }

        _price = initialPrice;
        _decimals = decimals_;
        symbol = symbol_;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, _price, block.timestamp, block.timestamp, 1);
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function setPrice(int256 newPrice) external onlyOwner {
        _price = newPrice;

        emit PriceUpdated(newPrice, msg.sender);
    }

    function addOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");

        isOwner[newOwner] = true;

        emit OwnerAdded(newOwner);
    }
}

/**
 * @title ManualChainlinkMockFeedFactory
 */
contract ManualChainlinkMockFeedFactory {
    address[] public allFeeds;

    event FeedCreated(
        address indexed feed,
        string symbol,
        int256 initialPrice,
        uint8 decimals,
        address[] owners
    );

    function createFeed(
        int256 initialPrice,
        uint8 decimals_,
        string memory symbol_,
        address[] memory owners_
    ) external returns (address feedAddress) {
        ManualChainlinkMockFeed feed = new ManualChainlinkMockFeed(
            initialPrice,
            decimals_,
            symbol_,
            owners_
        );

        feedAddress = address(feed);

        allFeeds.push(feedAddress);

        emit FeedCreated(
            feedAddress,
            symbol_,
            initialPrice,
            decimals_,
            owners_
        );
    }

    function getAllFeeds() external view returns (address[] memory) {
        return allFeeds;
    }

    function totalFeeds() external view returns (uint256) {
        return allFeeds.length;
    }
}