const { expect, assert } = require("chai");

describe("CrossMarginTrading.getHoldingAmount", function () {
    it("Should return empty for non-existent account", async function () {
        const Roles = await ethers.getContractFactory("Roles");
        const roles = await Roles.deploy();
        await roles.deployed();

        const CrossMarginTrading = await ethers.getContractFactory("CrossMarginTrading");
        const marginTrading = await CrossMarginTrading.deploy(roles.address);
        await marginTrading.deployed();

        const nonexistAddress = '0x0000000000000000000000000000000000000001';
        const holdingAmounts = await marginTrading.getHoldingAmounts(nonexistAddress);

        expect(holdingAmounts).to.be.a('array');
        expect(holdingAmounts).to.have.lengthOf(2);
        expect(holdingAmounts).to.have.property('holdingAmounts').with.lengthOf(0);
        expect(holdingAmounts).to.have.property('holdingTokens').with.lengthOf(0);
    });
});