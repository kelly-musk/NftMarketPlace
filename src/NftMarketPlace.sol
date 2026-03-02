// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title NFT Marketplace
/// @notice Escrow-based marketplace where sellers list ERC721 tokens and buyers purchase with ETH.
contract NFTMarketplace is Ownable, ReentrancyGuard {
    /// @param _feePercent Protocol fee percentage in whole numbers (e.g. 5 = 5%).
    /// @param _treasury Address that receives protocol fees from each sale.
    constructor(uint256 _feePercent, address _treasury) Ownable(msg.sender) {
        // Treasury must be valid to avoid permanently losing protocol fees.
        require(_treasury != address(0), "Treasury cannot be address zero");
        // Fee is capped at 100% to keep arithmetic and behavior sane.
        require(_feePercent <= 100, "Fee too high");

        feePercent = _feePercent;
        treasury = _treasury;
    }

    /// @dev Mapping key is keccak256(abi.encode(tokenContract, tokenId)).
    mapping(bytes32 => Listing) public listings;
    /// @notice Protocol fee percentage applied to each successful purchase.
    uint256 public feePercent;
    /// @notice Address that receives protocol fees.
    address public treasury;

    /// @notice Listing data tracked while an NFT is active on the market.
    struct Listing {
        /// @dev Account that listed the NFT and receives sale proceeds.
        address seller;
        /// @dev Total buy price in wei.
        uint256 price;
        /// @dev True only while the listing is available for purchase.
        bool isActive;
    }

    /// @notice Emitted when an NFT is listed into escrow.
    event NftListed(address indexed seller, address indexed tokenContract, uint256 indexed tokenId, uint256 price);
    /// @notice Emitted when a seller cancels an active listing.
    event NftCancelled(address indexed seller, address indexed tokenContract, uint256 indexed tokenId);
    /// @notice Emitted when a buyer purchases an active listing.
    event NftBought(
        address indexed buyer, address indexed seller, address indexed tokenContract, uint256 tokenId, uint256 price
    );

    /// @dev Deterministic key for listing lookup across all marketplace functions.
    function _listingId(address _tokenContract, uint256 _tokenId) internal pure returns (bytes32) {
        return keccak256(abi.encode(_tokenContract, _tokenId));
    }

    /// @notice Owner-only admin function to update fee percentage.
    /// @param _feePercent New fee percentage (0-100).
    function setFeePercent(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= 100, "Fee too high");
        feePercent = _feePercent;
    }

    /// @notice Owner-only admin function to update fee recipient.
    /// @param _treasury New treasury address.
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
    }

    /// @notice Lists an owned and approved NFT by moving it into contract escrow.
    /// @param _tokenContract ERC721 contract address.
    /// @param _tokenId Token id to list.
    /// @param _price Sale price in wei.
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
        // Prevent duplicate active listing for the same NFT.
        require(!listing.isActive, "Already listed");

        // Transfer NFT to marketplace escrow.
        nft.transferFrom(msg.sender, address(this), _tokenId);

        // Persist listing details after escrow transfer succeeds.
        listing.seller = msg.sender;
        listing.price = _price;
        listing.isActive = true;

        emit NftListed(msg.sender, _tokenContract, _tokenId, _price);
    }

    /// @notice Cancels an active listing and sends NFT back to its seller.
    /// @param _tokenContract ERC721 contract address.
    /// @param _tokenId Token id to cancel.
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

    /// @notice Purchases an active listing, pays treasury/seller, and transfers NFT to buyer.
    /// @param _tokenContract ERC721 contract address.
    /// @param _tokenId Token id to buy.
    function buyNft(address _tokenContract, uint256 _tokenId) external payable nonReentrant {
        bytes32 listingId = _listingId(_tokenContract, _tokenId);
        Listing storage listing = listings[listingId];

        require(listing.isActive, "NFT not for sale");
        require(msg.value == listing.price, "Incorrect payment amount");
        require(msg.sender != listing.seller, "Seller cannot buy own NFT");

        // Compute protocol share and seller payout from total payment.
        uint256 protocolFee = (msg.value * feePercent) / 100;
        uint256 sellerProceeds = msg.value - protocolFee;

        // Deactivate listing first (CEI pattern).
        listing.isActive = false;

        // Send protocol fee.
        (bool feeSent,) = treasury.call{value: protocolFee}("");
        require(feeSent, "Fee transfer failed");
        // Send proceeds to seller.
        (bool sellerPaid,) = listing.seller.call{value: sellerProceeds}("");
        require(sellerPaid, "Seller payout failed");

        // Transfer NFT to buyer.
        IERC721(_tokenContract).transferFrom(address(this), msg.sender, _tokenId);

        emit NftBought(msg.sender, listing.seller, _tokenContract, _tokenId, msg.value);
    }
}
