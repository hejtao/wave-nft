// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IMinterManager} from "./interfaces/IMinterManager.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ILockable} from "./interfaces/ILockable.sol";
import {ERC721BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import {ERC2771ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract Wave is
    ERC721Upgradeable,
    OwnableUpgradeable,
    IMinterManager,
    PausableUpgradeable,
    ILockable,
    ERC721BurnableUpgradeable,
    ERC2771ContextUpgradeable,
    UUPSUpgradeable
{
    mapping(address => bool) private _minters;
    mapping(uint256 => bool) private _lockedTokens;
    mapping(uint256 => uint256) private _lockTime;
    string private _baseURL;

    modifier onlyMinter() {
        require(_minters[_msgSender()], "Not minter");
        _;
    }

    // {trustedForwarder} is initialized as a immutable variable of Wave, which locates at the code segment
    // so the proxy can access the {trustedForwarder} without accessing its storage
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder)
        ERC2771ContextUpgradeable(trustedForwarder)
    {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC721_init("Wave", "WV");
        __Ownable_init(_msgSender());
        __Pausable_init();
        __ERC721Burnable_init();
    }

    function mint(address to, uint256 tokenId) public whenNotPaused onlyMinter {
        _safeMint(to, tokenId);
    }

    function isMinter(address account) public view returns (bool) {
        return _minters[account];
    }

    function addMinter(address account)
        external
        override
        whenNotPaused
        onlyOwner
    {
        _minters[account] = true;
    }

    function removeMinter(address account)
        external
        override
        whenNotPaused
        onlyOwner
    {
        delete _minters[account];
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function lockTokens(uint256[] calldata tokenIds, uint256 lockTime)
        external
        override
        whenNotPaused
    {
        require(lockTime > 0, "Lock time must be greater than 0");

        // change isMinter to public
        if (isMinter(_msgSender())) {
            for (uint256 i = 0; i < tokenIds.length; i++) {
                _requireOwned(tokenIds[i]);
                _lockedTokens[tokenIds[i]] = true;
                _lockTime[tokenIds[i]] = block.timestamp + lockTime;
            }
            return;
        }

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(ownerOf(tokenId) == _msgSender(), "Not owner or minter");

            _lockedTokens[tokenId] = true;
            _lockTime[tokenId] = block.timestamp + lockTime;
        }
    }

    function unlockTokens(uint256[] calldata tokenIds)
        external
        override
        whenNotPaused
    {
        if (isMinter(_msgSender())) {
            for (uint256 i = 0; i < tokenIds.length; i++) {
                _requireOwned(tokenIds[i]);
                delete _lockedTokens[tokenIds[i]];
                delete _lockTime[tokenIds[i]];
            }
            return;
        }

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(ownerOf(tokenId) == _msgSender(), "Not owner or minter");

            delete _lockedTokens[tokenIds[i]];
            delete _lockTime[tokenIds[i]];
        }
    }

    function isTokenLocked(uint256 tokenId)
        public
        view
        override
        returns (bool)
    {
        _requireOwned(tokenId);
        return _lockedTokens[tokenId];
    }

    function burn(uint256 tokenId) public override {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        super.burn(tokenId);
    }

    function _msgSender()
        internal
        view
        virtual
        override(ERC2771ContextUpgradeable, ContextUpgradeable)
        returns (address sender)
    {
        return super._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(ERC2771ContextUpgradeable, ContextUpgradeable)
        returns (bytes calldata)
    {
        return super._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        virtual
        override(ERC2771ContextUpgradeable, ContextUpgradeable)
        returns (uint256)
    {
        return super._contextSuffixLength();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _baseURI() internal view virtual override  returns (string memory) {
        return _baseURL;
    }

    function setBaseURI(string calldata url) public {
        _baseURL = url;
    }
}
