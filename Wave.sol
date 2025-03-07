// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMinterManager} from "./interfaces/IMinterManager.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ILockable} from "./interfaces/ILockable.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Wave is ERC721, Ownable, IMinterManager, Pausable, ILockable, ERC721Burnable, ReentrancyGuard {
    mapping(address => bool) private _minters;
    mapping(uint256 => bool) private _lockedTokens;
    mapping(uint256 => uint256) private _lockTime;

    constructor() ERC721("Wave", "WV") Ownable(_msgSender()) {}

    modifier onlyMinter() {
        require(_minters[_msgSender()], "Not minter");
        _;
    }

    function mint(address to, uint256 tokenId) public whenNotPaused onlyMinter {
        _safeMint(to, tokenId);
    }

    function isMinter(address account) public view returns (bool) {
        return _minters[account];
    }

    function addMinter(address account) external override whenNotPaused onlyOwner{
        _minters[account] = true;
    }

    function removeMinter(address account) external override whenNotPaused onlyOwner{
        delete _minters[account];
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function lockTokens(uint256[] calldata tokenIds, uint256 lockTime)external override whenNotPaused{
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

    function unlockTokens(uint256[] calldata tokenIds)external override whenNotPaused{
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

    function isTokenLocked(uint256 tokenId) public view  override returns (bool) {
        _requireOwned(tokenId);
        return _lockedTokens[tokenId];
    }

    function burn(uint256 tokenId) public  override whenNotPaused {
        require(ownerOf(tokenId) == _msgSender(),"Not owner");
        super.burn(tokenId);
    }
}
