// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {NFTMarketplace} from "../src/NftMarketPlace.sol";

contract MockERC721 is ERC721 {
    constructor() ERC721("Mock NFT", "MNFT") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract NftMarketPlaceTest is Test {
    NFTMarketplace internal market;
    MockERC721 internal nft;

    address internal seller = makeAddr("seller");
    address internal buyer = makeAddr("buyer");
    address internal treasury = makeAddr("treasury");
    address internal stranger = makeAddr("stranger");

    uint256 internal constant FEE_PERCENT = 5;
    uint256 internal constant TOKEN_ID = 1;
    uint256 internal constant PRICE = 1 ether;

    function setUp() public {
        market = new NFTMarketplace(FEE_PERCENT, treasury);
        nft = new MockERC721();
        nft.mint(seller, TOKEN_ID);
    }

    function _listingId(address tokenContract, uint256 tokenId) internal pure returns (bytes32) {
        return keccak256(abi.encode(tokenContract, tokenId));
    }

    function _approveAndList() internal {
        vm.startPrank(seller);
        nft.approve(address(market), TOKEN_ID);
        market.listNft(address(nft), TOKEN_ID, PRICE);
        vm.stopPrank();
    }

    function test_ListNft_TransfersToEscrowAndStoresListing() public {
        _approveAndList();

        assertEq(nft.ownerOf(TOKEN_ID), address(market));

        (address listingSeller, uint256 listingPrice, bool isActive) = market.listings(_listingId(address(nft), TOKEN_ID));
        assertEq(listingSeller, seller);
        assertEq(listingPrice, PRICE);
        assertTrue(isActive);
    }

    function test_ListNft_RevertsWhenNotApproved() public {
        vm.prank(seller);
        vm.expectRevert("Marketplace not approved");
        market.listNft(address(nft), TOKEN_ID, PRICE);
    }

    function test_CancelListing_ReturnsNftToSeller() public {
        _approveAndList();

        vm.prank(seller);
        market.cancelListing(address(nft), TOKEN_ID);

        assertEq(nft.ownerOf(TOKEN_ID), seller);
        (, , bool isActive) = market.listings(_listingId(address(nft), TOKEN_ID));
        assertFalse(isActive);
    }

    function test_CancelListing_RevertsForNonSeller() public {
        _approveAndList();

        vm.prank(stranger);
        vm.expectRevert("Not seller");
        market.cancelListing(address(nft), TOKEN_ID);
    }

    function test_BuyNft_TransfersNftAndSplitsPayment() public {
        _approveAndList();

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

        (, , bool isActive) = market.listings(_listingId(address(nft), TOKEN_ID));
        assertFalse(isActive);
    }

    function test_BuyNft_RevertsWithIncorrectPayment() public {
        _approveAndList();

        vm.deal(buyer, PRICE);
        vm.prank(buyer);
        vm.expectRevert("Incorrect payment amount");
        market.buyNft{value: PRICE - 1}(address(nft), TOKEN_ID);
    }

    function test_BuyNft_RevertsWhenSellerTriesToBuyOwnListing() public {
        _approveAndList();

        vm.deal(seller, PRICE);
        vm.prank(seller);
        vm.expectRevert("Seller cannot buy own NFT");
        market.buyNft{value: PRICE}(address(nft), TOKEN_ID);
    }
}
