// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./lib/BokkyPooBahsDateTimeLibrary.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import "hardhat/console.sol";
// import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract Payment is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    event Pay(
        address userAddress,
        uint256 itemId,
        uint256 price,
        uint256 refund,
        string payload,
        address token,
        uint256 amount
    );
    event AddItem(
        uint256 itemId,
        uint256 price,
        bool isUnlimited,
        uint256 dailyLimit
    );
    event UpdateItem(
        uint256 itemId,
        uint256 price,
        bool isUnlimited,
        uint256 dailyLimit
    );
    event UpdateDiscount(address token, uint256 itemId, uint256 discount);
    event UpdateOracle(address token, address oracle);

    struct Item {
        uint256 price; // in usd, decimals 8
        bool isRegistered;
        bool isUnlimited;
        uint256 dailyLimit;
    }

    uint256 public priceAge;
    mapping(address => mapping(uint256 => uint256)) public userPayTime; // user => itemId => timestamp
    mapping(address => mapping(uint256 => uint256)) public userDailyPayCount; // user => itemId => count
    mapping(uint256 => Item) public items; // item id => item
    address public treasury;
    mapping(address => IPyth) public priceFeeds; // token => oracle
    mapping(address => bytes32) public priceFeedIds; // token => feedid
    mapping(address => mapping(uint256 => uint256)) public discounts; // token => itemId => discount

    function initialize(
        address initialOwner,
        address _treasury,
        address[] calldata tokens,
        address[] calldata oracles,
        bytes32[] calldata feedIds
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init(initialOwner);
        treasury = _treasury;

        priceAge = 3600;

        require(tokens.length == oracles.length && tokens.length == feedIds.length, "Invalid Length");

        for (uint256 i = 0; i < tokens.length; i++) {
            priceFeeds[tokens[i]] = IPyth(oracles[i]);
            priceFeedIds[tokens[i]] = feedIds[i];
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function pay(
        uint256 itemId,
        address token,
        uint256 maxAmount,
        string calldata payload
    ) external payable virtual nonReentrant {
        Item memory item = items[itemId];
        require(item.isRegistered, "Item Not Registered");
        require(
            address(priceFeeds[token]) != address(0),
            "Token Not Registered"
        );
        address user = msg.sender;
        require(!_isContract(user), "ONLY EOA");

        if (!item.isUnlimited) {
            _checkDailyPayLimit(itemId, user);
        }
        uint256 refund = 0;
        uint256 amount = getAmount(token, item.price);
        uint256 discount = discounts[token][itemId];
        amount = (amount * (100 - discount)) / 100;

        require(amount <= maxAmount, "Exceed Max Amount");
        if (token == address(0)) {
            require(msg.value >= amount, "Insufficient Value");
            if (msg.value - amount > 0) {
                refund = msg.value - amount;
            }
            (bool ok, ) = treasury.call{value: amount}("");
            require(ok, "Treasury Fail to Call");

            if (refund > 0) {
                (bool ok2, ) = user.call{value: refund}("");
                require(ok2, "User Fail to Call");
            }
        } else {
            require(
                IERC20(token).balanceOf(user) >= amount,
                "Insufficient Balance"
            );
            IERC20(token).safeTransferFrom(user, address(treasury), amount);
        }
        emit Pay(user, itemId, item.price, refund, payload, token, amount);
    }

    function addItem(
        uint256 itemId,
        uint256 price,
        bool isUnlimited,
        uint256 dailyLimit
    ) external virtual onlyOwner {
        _addItem(itemId, price, isUnlimited, dailyLimit);
    }

    function addItems(
        uint256[] calldata itemIds,
        uint256[] calldata prices,
        bool[] calldata isUnlimited,
        uint256[] calldata dailyLimits
    ) external virtual onlyOwner {
        uint256 length = itemIds.length;
        require(
            prices.length == length &&
                isUnlimited.length == length &&
                dailyLimits.length == length,
            "Invalid Item"
        );

        for (uint256 i = 0; i < itemIds.length; i++) {
            _addItem(itemIds[i], prices[i], isUnlimited[i], dailyLimits[i]);
        }
    }

    function getAmount(
        address token,
        uint256 unitPriceInUsd
    ) public view virtual returns (uint256) {
        uint8 decimals = 18;
        return (unitPriceInUsd * (10 ** decimals)) / getUsdPrice(token);
    }

    function getUsdPrice(address token) public view virtual returns (uint256) {
        PythStructs.Price memory currentBasePrice = priceFeeds[token]
            .getPriceNoOlderThan(priceFeedIds[token], priceAge);
        require(currentBasePrice.price >= 0, "Value must be non-negative");

        return uint256(int256(currentBasePrice.price));
    }

    function setPriceAge(uint256 _age) external onlyOwner {
        priceAge = _age;
    }

    function getTokenAmountPerItem(
        address token,
        uint256 itemId
    ) public view returns (uint256) {
        return getAmount(token, items[itemId].price);
    }

    function updateDiscount(
        address token,
        uint256 itemId,
        uint256 discount
    ) external virtual onlyOwner {
        _updateDiscount(token, itemId, discount);
    }

    function updateDiscounts(
        address[] calldata tokens,
        uint256[] calldata itemIds,
        uint256[] calldata discountsArr
    ) external virtual onlyOwner {
        uint256 length = tokens.length;
        require(
            itemIds.length == length && discountsArr.length == length,
            "Invalid Discount"
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            _updateDiscount(tokens[i], itemIds[i], discountsArr[i]);
        }
    }

    function _updateDiscount(
        address token,
        uint256 itemId,
        uint256 discount
    ) internal virtual {
        require(items[itemId].isRegistered, "Item Not Registered");
        require(discount >= 0 && discount < 100, "Invalid Discount Range");
        discounts[token][itemId] = discount;
        emit UpdateDiscount(token, itemId, discount);
    }

    function _addItem(
        uint256 itemId,
        uint256 price,
        bool isUnlimited,
        uint256 dailyLimit
    ) internal virtual {
        require(!items[itemId].isRegistered, "Item Already Registered");
        require(
            isUnlimited ? dailyLimit == 0 : dailyLimit > 0,
            "Invalid Limit"
        );
        items[itemId] = Item(price, true, isUnlimited, dailyLimit);
        emit AddItem(itemId, price, isUnlimited, dailyLimit);
    }

    function updateItem(
        uint256 itemId,
        uint256 price,
        bool isUnlimited,
        uint256 dailyLimit
    ) external virtual onlyOwner {
        _updateItem(itemId, price, isUnlimited, dailyLimit);
    }

    function updateItems(
        uint256[] calldata itemIds,
        uint256[] calldata prices,
        bool[] calldata isUnlimited,
        uint256[] calldata dailyLimits
    ) external virtual onlyOwner {
        uint256 length = itemIds.length;
        require(
            prices.length == length &&
                isUnlimited.length == length &&
                dailyLimits.length == length,
            "Invalid Item"
        );

        for (uint256 i = 0; i < itemIds.length; i++) {
            _updateItem(itemIds[i], prices[i], isUnlimited[i], dailyLimits[i]);
        }
    }

    function _updateItem(
        uint256 itemId,
        uint256 price,
        bool isUnlimited,
        uint256 dailyLimit
    ) internal virtual {
        require(items[itemId].isRegistered, "Item Not Registered");
        require(
            isUnlimited ? dailyLimit == 0 : dailyLimit > 0,
            "Invalid Limit"
        );
        items[itemId].price = price;
        items[itemId].isUnlimited = isUnlimited;
        items[itemId].dailyLimit = dailyLimit;
        emit UpdateItem(itemId, price, isUnlimited, dailyLimit);
    }

    function updateOracle(
        address token,
        IPyth oracle,
        bytes32 feedId
    ) external virtual onlyOwner {
        priceFeeds[token] = IPyth(oracle);
        priceFeedIds[token] = feedId;
        emit UpdateOracle(token, address(oracle));
    }

    function _checkDailyPayLimit(
        uint256 itemId,
        address user
    ) internal virtual {
        require(items[itemId].dailyLimit > 0, "Daily Limit is 0");
        uint256 lastTime = userPayTime[user][itemId];
        uint256 currentTime = block.timestamp;

        uint256 remainOneDayInSecond = BokkyPooBahsDateTimeLibrary
            .SECONDS_PER_DAY -
            (lastTime % BokkyPooBahsDateTimeLibrary.SECONDS_PER_DAY);
        if (lastTime == 0 || lastTime + remainOneDayInSecond >= currentTime) {
            require(
                userDailyPayCount[user][itemId] < items[itemId].dailyLimit,
                "Exceed Daily Pay Limit"
            );
            userDailyPayCount[user][itemId]++;
        } else {
            userDailyPayCount[user][itemId] = 1;
        }
        userPayTime[user][itemId] = currentTime;
    }

    function _isContract(address addr) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}





