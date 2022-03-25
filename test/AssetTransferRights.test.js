const { expect } = require("chai");
const { ethers } = require("hardhat");
const utils = ethers.utils;
const Iface = require("./sharedIfaces.js");

describe("AssetTransferRights", function() {

	let ATR, atr;
	let wallet, walletOther;
	let factory;
	let T20, T721, T1155;
	let t20, t721, t1155;
	let owner, other;

	before(async function() {
		ATR = await ethers.getContractFactory("AssetTransferRights");
		T20 = await ethers.getContractFactory("T20");
		T721 = await ethers.getContractFactory("T721");
		T1155 = await ethers.getContractFactory("T1155");

		[owner, other] = await ethers.getSigners();
	});

	beforeEach(async function() {
		atr = await ATR.deploy();
		await atr.deployed();

		factory = await ethers.getContractAt("PWNWalletFactory", atr.walletFactory());

		t20 = await T20.deploy();
		await t20.deployed();

		t721 = await T721.deploy();
		await t721.deployed();

		t1155 = await T1155.deploy();
		await t1155.deployed();

		const walletTx = await factory.connect(owner).newWallet();
		const walletRes = await walletTx.wait();
		wallet = await ethers.getContractAt("PWNWallet", walletRes.events[1].args.walletAddress);

		const walletOtherTx = await factory.connect(other).newWallet();
		const walletOtherRes = await walletOtherTx.wait();
		walletOther = await ethers.getContractAt("PWNWallet", walletOtherRes.events[1].args.walletAddress);
	});


	describe("Mint", function() {

		const tokenId = 123;
		const tokenAmount = 3323;

		beforeEach(async function() {
			await t20.mint(wallet.address, tokenAmount);
			await t721.mint(wallet.address, tokenId);
			await t1155.mint(wallet.address, tokenId, tokenAmount);
		});


		it("Should fail when sender is not PWN Wallet", async function() {
			await t721.mint(other.address, 333);

			await expect(
				atr.connect(other).mintAssetTransferRightsToken( [t721.address, 1, 1, 333] )
			).to.be.revertedWith("Mint is permitted only from PWN Wallet");
		});

		it("Should fail when sender is not asset owner", async function() {
			await t721.mint(owner.address, 3232);

			await expect(
				wallet.mintAssetTransferRightsToken([t721.address, 1, 1, 3232])
			).to.be.revertedWith("Not enough balance to tokenize asset transfer rights");
		});

		it("Should fail when trying to tokenize zero address asset", async function() {
			const calldata = Iface.ATR.encodeFunctionData("mintAssetTransferRightsToken", [ [ethers.constants.AddressZero, 1, 1, 3232] ]);
			await expect(
				wallet.mintAssetTransferRightsToken([ethers.constants.AddressZero, 1, 1, 3232])
			).to.be.revertedWith("Cannot tokenize zero address asset");
		});

		it("Should fail when asset is invalid", async function() {
			await expect(
				wallet.mintAssetTransferRightsToken([t721.address, 1, 0, tokenId])
			).to.be.revertedWith("Amount has to be bigger than zero");
		});

		it("Should fail when ERC20 asset doesn't have enough untokenized balance to tokenize without any tokenized asset", async function() {
			await expect(
				wallet.mintAssetTransferRightsToken([t20.address, 0, tokenAmount + 1, 0])
			).to.be.revertedWith("Not enough balance to tokenize asset transfer rights");
		});

		it("Should fail when ERC1155 asset doesn't have enough untokenized balance to tokenize without any tokenized asset", async function() {
			await expect(
				wallet.mintAssetTransferRightsToken([t1155.address, 2, tokenAmount + 1, tokenId])
			).to.be.revertedWith("Not enough balance to tokenize asset transfer rights");
		});

		it("Should fail when ERC20 asset doesn't have enough untokenized balance to tokenize with some tokenized asset", async function() {
			await wallet.mintAssetTransferRightsToken([t20.address, 0, tokenAmount - 20, 0]);

			await expect(
				wallet.mintAssetTransferRightsToken([t20.address, 0, 21, 0])
			).to.be.revertedWith("Not enough balance to tokenize asset transfer rights");
		});

		it("Should fail when ERC721 asset is already tokenised", async function() {
			await wallet.mintAssetTransferRightsToken([t721.address, 1, 1, tokenId]);

			await expect(
				wallet.mintAssetTransferRightsToken([t721.address, 1, 1, tokenId])
			).to.be.revertedWith("Not enough balance to tokenize asset transfer rights");
		});

		it("Should fail when ERC1155 asset doesn't have enough untokenized balance to tokenize with some tokenized asset", async function() {
			await wallet.mintAssetTransferRightsToken([t1155.address, 2, tokenAmount - 20, tokenId]);

			await expect(
				wallet.mintAssetTransferRightsToken([t1155.address, 2, 21, tokenId])
			).to.be.revertedWith("Not enough balance to tokenize asset transfer rights");
		});

		it("Should tokenize ERC20 asset when untokenized balance is sufficient", async function() {
			await wallet.mintAssetTransferRightsToken([t20.address, 0, tokenAmount - 20, 0]);

			await expect(
				wallet.mintAssetTransferRightsToken([t20.address, 0, 20, 0])
			).to.not.be.reverted;
		});

		it("Should tokenize ERC1155 asset when untokenized balance is sufficient", async function() {
			await wallet.mintAssetTransferRightsToken([t1155.address, 2, tokenAmount - 20, tokenId]);

			await expect(
				wallet.mintAssetTransferRightsToken([t1155.address, 2, 20, tokenId])
			).to.not.be.reverted;
		});

		it("Should increate ATR token id", async function() {
			const lastTokenId = await atr.lastTokenId();

			await wallet.mintAssetTransferRightsToken([t721.address, 1, 1, tokenId]);

			expect(await atr.lastTokenId()).to.equal(lastTokenId + 1);
		});

		it("Should store tokenized asset data", async function() {
			await wallet.mintAssetTransferRightsToken([t721.address, 1, 1, tokenId]);

			const asset = await atr.getAsset(1);
			expect(asset.assetAddress).to.equal(t721.address);
			expect(asset.category).to.equal(1);
			expect(asset.amount).to.equal(1);
			expect(asset.id).to.equal(tokenId);
		});

		it("Should store that sender has tokenized asset in wallet", async function() {
			await wallet.mintAssetTransferRightsToken([t721.address, 1, 1, tokenId]);

			const calldata = Iface.ATR.encodeFunctionData("ownedAssetATRIds", []);
			const ownedAssets = await wallet.callStatic.execute(atr.address, calldata);
			const decodedOwnedAssets = Iface.ATR.decodeFunctionResult("ownedAssetATRIds", ownedAssets);
			expect(decodedOwnedAssets[0][0].toNumber()).to.equal(1);
		});

		it("Should mint TR token", async function() {
			await expect(
				wallet.mintAssetTransferRightsToken([t721.address, 1, 1, tokenId])
			).to.not.be.reverted;

			expect(await atr.ownerOf(1)).to.equal(wallet.address);
		});

	});


	describe("Burn", function() {

		const tokenId = 123;

		beforeEach(async function() {
			await t721.mint(wallet.address, tokenId);

			// ATR token with id 1
			await wallet.mintAssetTransferRightsToken([t721.address, 1, 1, tokenId]);
		});


		it("Should fail when sender is not ATR token owner", async function() {
			// Transfer ATR token to `other`
			const calldata = Iface.ERC721.encodeFunctionData("transferFrom", [wallet.address, other.address, 1]);
			await wallet.execute(atr.address, calldata);

			await expect(
				wallet.burnAssetTransferRightsToken(1)
			).to.be.revertedWith("Sender is not ATR token owner");
		});

		it("Should fail when ATR token is not minted", async function() {
			await expect(
				wallet.burnAssetTransferRightsToken(2)
			).to.be.revertedWith("Asset transfer rights are not tokenized");
		});

		it("Should fail when sender is not tokenized asset owner", async function() {
			// Transfer asset to `otherWallet`
			const calldata = Iface.ATR.encodeFunctionData("transferAssetFrom", [wallet.address, walletOther.address, 1, false]);
			await wallet.execute(atr.address, calldata);

			await expect(
				wallet.burnAssetTransferRightsToken(1)
			).to.be.revertedWith("Sender does not have enough amount of tokenized asset");
		});

		it("Should clear stored tokenized asset data", async function() {
			await wallet.burnAssetTransferRightsToken(1);

			const asset = await atr.getAsset(1);
			expect(asset.assetAddress).to.equal(ethers.constants.AddressZero);
			expect(asset.category).to.equal(0);
			expect(asset.amount).to.equal(0);
			expect(asset.id).to.equal(0);
		});

		it("Should remove stored tokenized asset info from senders wallet", async function() {
			await wallet.burnAssetTransferRightsToken(1);

			const calldata = Iface.ATR.encodeFunctionData("ownedAssetATRIds", []);
			const ownedAssets = await wallet.callStatic.execute(atr.address, calldata);
			const decodedOwnedAssets = Iface.ATR.decodeFunctionResult("ownedAssetATRIds", ownedAssets);
			expect(decodedOwnedAssets[0]).to.be.empty;
		});

		it("Should burn ATR token", async function() {
			await expect(
				wallet.burnAssetTransferRightsToken(1)
			).to.not.be.reverted;

			await expect(
				atr.ownerOf(1)
			).to.be.reverted;
		});

	});


	// Done
	describe("Transfer asset from", async function() {

		const tokenId = 123;
		const tokenAmount = 12332;

		beforeEach(async function() {
			await t20.mint(wallet.address, tokenAmount);
			await t721.mint(wallet.address, tokenId);
			await t1155.mint(wallet.address, tokenId, tokenAmount);

			// ATR token with id 1
			await wallet.mintAssetTransferRightsToken([t20.address, 0, tokenAmount, 0]);
			// ATR token with id 2
			await wallet.mintAssetTransferRightsToken([t721.address, 1, 1, tokenId]);
			// ATR token with id 3
			await wallet.mintAssetTransferRightsToken([t1155.address, 2, tokenAmount, tokenId]);
		});


		it("Should fail when token rights are not tokenized", async function() {
			await expect(
				atr.transferAssetFrom(wallet.address, walletOther.address, 4, false)
			).to.be.revertedWith("Transfer rights are not tokenized");
		});

		it("Should fail when sender is not ATR token owner", async function() {
			await expect(
				atr.connect(owner).transferAssetFrom(wallet.address, walletOther.address, 2, false)
			).to.be.revertedWith("Sender is not ATR token owner");
		});

		it("Should fail when asset is not in senders wallet", async function() {
			// Transfer ATR token to `other`
			const calldata = Iface.ERC721.encodeFunctionData("transferFrom", [wallet.address, other.address, 2]);
			await wallet.execute(atr.address, calldata);

			// Transfer asset from `owner`s wallet via ATR token
			await atr.connect(other).transferAssetFrom(wallet.address, walletOther.address, 2, false);

			// Try to again transfer asset from `owner`s wallet via ATR token
			await expect(
				atr.connect(other).transferAssetFrom(wallet.address, walletOther.address, 2, false)
			).to.be.revertedWith("Asset is not in target wallet");
		});

		it("Should fail when transferring asset to same address", async function() {
			// Transfer ATR token to `other`
			const calldata = Iface.ERC721.encodeFunctionData("transferFrom", [wallet.address, other.address, 2]);
			await wallet.execute(atr.address, calldata);

			// Transfer asset from and to `owner`s wallet via ATR token
			await expect(
				atr.connect(other).transferAssetFrom(wallet.address, wallet.address, 2, false)
			).to.be.revertedWith("Transferring asset to same address");
		});

		it("Should remove stored tokenized asset info from senders wallet", async function() {
			// Transfer ATR token to `other`
			let calldata = Iface.ERC721.encodeFunctionData("transferFrom", [wallet.address, other.address, 2]);
			await wallet.execute(atr.address, calldata);

			// Transfer asset from `owner`s wallet via ATR token
			await atr.connect(other).transferAssetFrom(wallet.address, walletOther.address, 2, false);

			// Asset is no longer in `wallet`
			calldata = Iface.ATR.encodeFunctionData("ownedAssetATRIds", []);
			const ownedAssets = await wallet.callStatic.execute(atr.address, calldata);
			const decodedOwnedAssets = Iface.ATR.decodeFunctionResult("ownedAssetATRIds", ownedAssets);
			expect(decodedOwnedAssets[0].map(bn => bn.toNumber())).to.not.contain(2);
		});

		it("Should transfer ERC20 asset when sender has tokenized transfer rights", async function() {
			// Transfer ATR token to `other`
			const calldata = Iface.ERC721.encodeFunctionData("transferFrom", [wallet.address, other.address, 1]);
			await wallet.execute(atr.address, calldata);

			// Transfer asset from `owner`s wallet via ATR token
			await atr.connect(other).transferAssetFrom(wallet.address, walletOther.address, 1, false);

			// Assets owner is `walletOther` now
			expect(await t20.balanceOf(walletOther.address)).to.equal(tokenAmount);
		});

		it("Should transfer ERC721 asset when sender has tokenized transfer rights", async function() {
			// Transfer ATR token to `other`
			const calldata = Iface.ERC721.encodeFunctionData("transferFrom", [wallet.address, other.address, 2]);
			await wallet.execute(atr.address, calldata);

			// Transfer asset from `owner`s wallet via ATR token
			await atr.connect(other).transferAssetFrom(wallet.address, walletOther.address, 2, false);

			// Assets owner is `walletOther` now
			expect(await t721.ownerOf(tokenId)).to.equal(walletOther.address);
		});

		it("Should transfer ERC1155 asset when sender has tokenized transfer rights", async function() {
			// Transfer ATR token to `other`
			const calldata = Iface.ERC721.encodeFunctionData("transferFrom", [wallet.address, other.address, 3]);
			await wallet.execute(atr.address, calldata);

			// Transfer asset from `owner`s wallet via ATR token
			await atr.connect(other).transferAssetFrom(wallet.address, walletOther.address, 3, false);

			// Assets owner is `walletOther` now
			expect(await t1155.balanceOf(walletOther.address, tokenId)).to.equal(tokenAmount);
		});

		describe("Without `burnToken` flag", function() {

			it("Should store that sender has tokenized asset in wallet", async function() {
				// Transfer ATR token to `other`
				let calldata = Iface.ERC721.encodeFunctionData("transferFrom", [wallet.address, other.address, 2]);
				await wallet.execute(atr.address, calldata);

				// Transfer asset from `owner`s wallet via ATR token
				await atr.connect(other).transferAssetFrom(wallet.address, walletOther.address, 2, false);

				// Asset is in `walletOther`
				calldata = Iface.ATR.encodeFunctionData("ownedAssetATRIds", []);
				const ownedAssets = await walletOther.connect(other).callStatic.execute(atr.address, calldata);
				const decodedOwnedAssets = Iface.ATR.decodeFunctionResult("ownedAssetATRIds", ownedAssets);
				expect(decodedOwnedAssets[0].map(bn => bn.toNumber())).to.contain(2);
			});

			it("Should fail when transferring to other than PWN Wallet", async function() {
				// Transfer ATR token to `other`
				const calldata = Iface.ERC721.encodeFunctionData("transferFrom", [wallet.address, other.address, 2]);
				await wallet.execute(atr.address, calldata);

				// Transfer asset from `owner`s wallet via ATR token
				await expect(
					atr.connect(other).transferAssetFrom(wallet.address, other.address, 2, false)
				).to.be.revertedWith("Transfers of asset with tokenized transfer rights are allowed only to PWN Wallets");
			});

		});

		describe("With `burnToken` flag", function() {

			it("Should clear stored tokenized asset data", async function() {
				// Transfer ATR token to `other`
				const calldata = Iface.ERC721.encodeFunctionData("transferFrom", [wallet.address, other.address, 2]);
				await wallet.execute(atr.address, calldata);

				// Transfer asset from `owner`s wallet via ATR token
				await atr.connect(other).transferAssetFrom(wallet.address, walletOther.address, 2, true);

				await expect(atr.ownerOf(2)).to.be.reverted;
				const asset = await atr.getAsset(2);
				expect(asset.assetAddress).to.equal(ethers.constants.AddressZero);
				expect(asset.category).to.equal(0);
				expect(asset.amount).to.equal(0);
				expect(asset.id).to.equal(0);
			});

			it("Should burn ATR token", async function() {
				// Transfer ATR token to `other`
				const calldata = Iface.ERC721.encodeFunctionData("transferFrom", [wallet.address, other.address, 2]);
				await wallet.execute(atr.address, calldata);

				// Transfer asset from `owner`s wallet via ATR token
				await atr.connect(other).transferAssetFrom(wallet.address, walletOther.address, 2, true);

				// Assets owner is `walletOther` now
				expect(await t721.ownerOf(tokenId)).to.equal(walletOther.address);
			});

			it("Should transfer asset when transferring to other than PWN Wallet", async function() {
				// Transfer ATR token to `other`
				const calldata = Iface.ERC721.encodeFunctionData("transferFrom", [wallet.address, other.address, 2]);
				await wallet.execute(atr.address, calldata);

				// Transfer asset from `owner`s wallet via ATR token
				await atr.connect(other).transferAssetFrom(wallet.address, other.address, 2, true);

				expect(await t721.ownerOf(tokenId)).to.equal(other.address);
			});

		});

	});


	describe("Get asset", function() {

		xit("Should return stored asset");

	});


	describe("Owned asset ATR ids", function() {

		xit("Should return list of tokenized assets in senders wallet represented by their ATR token id");

	});

});
