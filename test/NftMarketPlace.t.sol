// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {NFTMarketplace} from "../src/NftMarketPlace.sol";

/// @notice Lightweight ERC721 used to test marketplace flows.
contract MockERC721 is ERC721 {
    constructor() ERC721("Mock NFT", "MNFT") {}

    /// @notice Test-only mint helper.
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

/// @notice Unit tests for listing, cancellation, and purchase behavior.
contract NftMarketPlaceTest is Test {
    /// @dev Contract under test.
    NFTMarketplace internal market;
    /// @dev Mock NFT collection used in tests.
    MockERC721 internal nft;

    /// @dev Primary listing owner.
    address internal seller = makeAddr("seller");
    /// @dev Account used to buy listed NFTs.
    address internal buyer = makeAddr("buyer");
    /// @dev Fee recipient configured on marketplace deploy.
    address internal treasury = makeAddr("treasury");
    /// @dev Non-owner account used for authorization-negative tests.
    address internal stranger = makeAddr("stranger");

    /// @dev Marketplace fee set to 5% for predictable payout checks.
    uint256 internal constant FEE_PERCENT = 5;
    /// @dev Shared token id used across tests.
    uint256 internal constant TOKEN_ID = 1;
    /// @dev Shared list price used across tests.
    uint256 internal constant PRICE = 1 ether;

    /// @notice Deploy fresh contracts and mint one NFT to seller before each test.
    function setUp() public {
        market = new NFTMarketplace(FEE_PERCENT, treasury);
        nft = new MockERC721();
        nft.mint(seller, TOKEN_ID);
    }

    /// @dev Mirrors marketplace key derivation so tests can read listing storage.
    function _listingId(address tokenContract, uint256 tokenId) internal pure returns (bytes32) {
        return keccak256(abi.encode(tokenContract, tokenId));
    }

    /// @dev Helper that approves token transfer and creates an active listing.
    function _approveAndList() internal {
        vm.startPrank(seller);
        nft.approve(address(market), TOKEN_ID);
        market.listNft(address(nft), TOKEN_ID, PRICE);
        vm.stopPrank();
    }

    /// @notice Verifies listing stores expected data and NFT moves into escrow.
    function test_ListNft_TransfersToEscrowAndStoresListing() public {
        _approveAndList();

        assertEq(nft.ownerOf(TOKEN_ID), address(market));

        (address listingSeller, uint256 listingPrice, bool isActive) =
            market.listings(_listingId(address(nft), TOKEN_ID));
        assertEq(listingSeller, seller);
        assertEq(listingPrice, PRICE);
        assertTrue(isActive);
    }

    /// @notice Verifies list action fails without prior marketplace approval.
    function test_ListNft_RevertsWhenNotApproved() public {
        vm.prank(seller);
        vm.expectRevert("Marketplace not approved");
        market.listNft(address(nft), TOKEN_ID, PRICE);
    }

    /// @notice Verifies seller can cancel and receive escrowed NFT back.
    function test_CancelListing_ReturnsNftToSeller() public {
        _approveAndList();

        vm.prank(seller);
        market.cancelListing(address(nft), TOKEN_ID);

        assertEq(nft.ownerOf(TOKEN_ID), seller);
        (,, bool isActive) = market.listings(_listingId(address(nft), TOKEN_ID));
        assertFalse(isActive);
    }

    /// @notice Verifies cancel is restricted to the listing seller.
    function test_CancelListing_RevertsForNonSeller() public {
        _approveAndList();

        vm.prank(stranger);
        vm.expectRevert("Not seller");
        market.cancelListing(address(nft), TOKEN_ID);
    }

    /// @notice Verifies buy transfers NFT and distributes ETH between treasury and seller.
    function test_BuyNft_TransfersNftAndSplitsPayment() public {
        _approveAndList();

        // Fund buyer and snapshot balances for delta assertions.
        vm.deal(buyer, 2 ether);
        uint256 sellerBalanceBefore = seller.balance;
        uint256 treasuryBalanceBefore = treasury.balance;
        uint256 expectedFee = (PRICE * FEE_PERCENT) / 100;
        uint256 expectedSellerProceeds = PRICE - expectedFee;

        vm.prank(buyer);
        market.buyNft{value: PRICE}(address(nft), TOKEN_ID);

        assertEq(nft.ownerOf(TOKEN_ID), buyer);
        assertEq(treasury.balance - treasuryBalanceBefore, expectedFee);
        assertEq(seller.balance - sellerBalanceBefore, expectedSellerProceeds);

        (,, bool isActive) = market.listings(_listingId(address(nft), TOKEN_ID));
        assertFalse(isActive);
    }

    /// @notice Verifies buy fails when ETH sent does not exactly match listing price.
    function test_BuyNft_RevertsWithIncorrectPayment() public {
        _approveAndList();

        vm.deal(buyer, PRICE);
        vm.prank(buyer);
        vm.expectRevert("Incorrect payment amount");
        market.buyNft{value: PRICE - 1}(address(nft), TOKEN_ID);
    }

    /// @notice Verifies seller cannot purchase their own listing.
    function test_BuyNft_RevertsWhenSellerTriesToBuyOwnListing() public {
        _approveAndList();

        vm.deal(seller, PRICE);
        vm.prank(seller);
        vm.expectRevert("Seller cannot buy own NFT");
        market.buyNft{value: PRICE}(address(nft), TOKEN_ID);
    }
}
