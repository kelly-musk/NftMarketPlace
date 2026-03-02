// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract NFTMarketplace is Ownable, ReentrancyGuard {
    constructor(uint256 _feePercent, address _treasury) Ownable(msg.sender) {
        require(_treasury != address(0), "Treasury cannot be address zero");
        require(_feePercent <= 100, "Fee too high");

        feePercent = _feePercent;
        treasury = _treasury;
    }

    mapping(bytes32 => Listing) public listings;
    uint256 public feePercent;
    address public treasury;

    struct Listing {
        address seller;
        uint256 price;
        bool isActive;
    }

    // events
    event NftListed(address indexed seller, address indexed tokenContract, uint256 indexed tokenId, uint256 price);
    event NftCancelled(address indexed seller, address indexed tokenContract, uint256 indexed tokenId);
    event NftBought(
        address indexed buyer, address indexed seller, address indexed tokenContract, uint256 tokenId, uint256 price
    );

    function _listingId(address _tokenContract, uint256 _tokenId) internal pure returns (bytes32) {
        return keccak256(abi.encode(_tokenContract, _tokenId));
    }

    function setFeePercent(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= 100, "Fee too high");
        feePercent = _feePercent;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
    }

    function listNft(address _tokenContract, uint256 _tokenId, uint256 _price) external nonReentrant {
        require(_price > 0, "Price must be greater than 0");
        IERC721 nft = IERC721(_tokenContract);
        bytes32 listingId = _listingId(_tokenContract, _tokenId);
        Listing storage listing = listings[listingId];

        // Check ownership and transfer approval.
        require(nft.ownerOf(_tokenId) == msg.sender, "Not owner");
        require(
            nft.getApproved(_tokenId) == address(this) || nft.isApprovedForAll(msg.sender, address(this)),
            "Marketplace not approved"
        );
        require(!listing.isActive, "Already listed");

        // Transfer NFT to marketplace escrow.
        nft.transferFrom(msg.sender, address(this), _tokenId);

        listing.seller = msg.sender;
        listing.price = _price;
        listing.isActive = true;

        emit NftListed(msg.sender, _tokenContract, _tokenId, _price);
    }

    function cancelListing(address _tokenContract, uint256 _tokenId) external nonReentrant {
        bytes32 listingId = _listingId(_tokenContract, _tokenId);
        Listing storage listing = listings[listingId];

        require(listing.isActive, "Listing not active");
        require(listing.seller == msg.sender, "Not seller");

        // Deactivate before external call (CEI pattern).
        listing.isActive = false;

        // Return NFT to seller.
        IERC721(_tokenContract).transferFrom(address(this), msg.sender, _tokenId);

        emit NftCancelled(msg.sender, _tokenContract, _tokenId);
    }

    function buyNft(address _tokenContract, uint256 _tokenId) external payable nonReentrant {
        bytes32 listingId = _listingId(_tokenContract, _tokenId);
        Listing storage listing = listings[listingId];

        require(listing.isActive, "NFT not for sale");
        require(msg.value == listing.price, "Incorrect payment amount");
        require(msg.sender != listing.seller, "Seller cannot buy own NFT");

        uint256 protocolFee = (msg.value * feePercent) / 100;
        uint256 sellerProceeds = msg.value - protocolFee;

        // Deactivate listing first (CEI pattern).
        listing.isActive = false;

        // Payouts.
        (bool feeSent,) = treasury.call{value: protocolFee}("");
        require(feeSent, "Fee transfer failed");
        (bool sellerPaid,) = listing.seller.call{value: sellerProceeds}("");
        require(sellerPaid, "Seller payout failed");

        // Transfer NFT to buyer.
        IERC721(_tokenContract).transferFrom(address(this), msg.sender, _tokenId);

        emit NftBought(msg.sender, listing.seller, _tokenContract, _tokenId, msg.value);
    }
}
