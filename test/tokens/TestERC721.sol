// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./ERC721Checkpointable.sol";

contract TestERC721 is ERC721Checkpointable() {
    constructor() ERC721("Test721", "TST721") { }

    function mint(address to, uint256 tokenId) public returns (bool) {
        _mint(to, tokenId);
        return true;
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "tokenURI";
    }
}
