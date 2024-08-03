// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract NFT {
    // 定义 Token 结构体，用于存储 NFT 信息
    struct Token {
        string name; // NFT 名称
        string description; // NFT 描述信息
        address owner; // NFT 所有者地址
    }

    // 使用 mapping 存储每个 NFT 的信息
    mapping(uint256 => Token) private tokens;
    // 使用 mapping 存储每个地址所拥有的 NFT ID 列表
    mapping(address => uint256[]) private ownerTokens;
    // 定义 NFT 所有权转移的授权映射
    mapping(uint256 => address) private tokenApprovals;
    // 记录下一个可用的 NFT ID
    uint256 nextTokenId = 1;

    // 创建 NFT 函数，用于创建一个新的 NFT，并将其分配给调用者
    function mint(string memory _name, string memory _description) public {
        tokens[nextTokenId] = Token(_name, _description, msg.sender);
        ownerTokens[msg.sender].push(nextTokenId);
        nextTokenId++;
    }

    // 销毁指定 NFT
    function burn(uint256 _tokenId) public {
        require(_tokenId >= 1 && _tokenId < nextTokenId, "Invalid token ID");
        Token storage token = tokens[_tokenId];
        require(token.owner == msg.sender, "You don't own this token");

        // 从 ownerTokens 数组中删除该 NFT ID
        uint256[] storage ownerTokenList = ownerTokens[msg.sender];
        for (uint256 i = 0; i < ownerTokenList.length; i++) {
            if (ownerTokenList[i] == _tokenId) {
                // 将该 NFT ID 与数组最后一个元素互换位置，然后删除数组最后一个元素
                ownerTokenList[i] = ownerTokenList[ownerTokenList.length - 1];
                ownerTokenList.pop();
                break;
            }
        }

        delete tokens[_tokenId];
    }

    // 转移指定 NFT 的所有权给目标地址
    function transfer(address _to, uint256 _tokenId) public {
        require(_to != address(0), "Invalid recipien");
        require(_tokenId >= 1 && _tokenId < nextTokenId, "Invalid token ID");
        Token storage token = tokens[_tokenId];
        require(token.owner == msg.sender, "You don't own this token");

        // 将 NFT 的所有权转移给目标地址
        token.owner = _to;

        // 更新 ownerTokens 数组
        uint256[] storage ownerTokenList = ownerTokens[msg.sender];
        for (uint256 i = 0; i < ownerTokenList.length; i++) {
            if (ownerTokenList[i] == _tokenId) {
                // 将该 NFT ID 与数组最后一个元素互换位置，然后删除数组最后一个元素
                ownerTokenList[i] = ownerTokenList[ownerTokenList.length - 1];
                ownerTokenList.pop();
                break;
            }
        }
        ownerTokens[_to].push(_tokenId);
    }

    // 获取指定 NFT 的信息
    function getNFT(
        uint256 _tokenId
    )
        public
        view
        returns (string memory name, string memory description, address owner)
    {
        require(_tokenId >= 1 && _tokenId < nextTokenId, "Invalid token ID");
        Token storage token = tokens[_tokenId];
        name = token.name;
        description = token.description;
        owner = token.owner;
    }

    // 获取指定地址所拥有的所有 NFT ID
    function getTokensByOwner(
        address _owner
    ) public view returns (uint256[] memory) {
        return ownerTokens[_owner];
    }

    // 将指定 NFT 的所有权转移给目标地址
    function transferFrom(address _from, address _to, uint256 _tokenId) public {
        require(_to != address(0), "Invalid recipient");
        require(_tokenId >= 1 && _tokenId < nextTokenId, "Invalid token ID");
        Token storage token = tokens[_tokenId];
        address owner = token.owner;

        // 判断调用者是否有操作权限
        require(msg.sender == owner || msg.sender == tokenApprovals[_tokenId]);

        // 将 NFT 的所有权转移给目标地址
        token.owner = _to;

        // 更新 ownerTokens 数组
        uint256[] storage fromTokenList = ownerTokens[_from];
        for (uint256 i = 0; i < fromTokenList.length; i++) {
            if (fromTokenList[i] == _tokenId) {
                // 将该 NFT ID 与数组最后一个元素互换位置，然后删除数组最后一个元素
                fromTokenList[i] = fromTokenList[fromTokenList.length - 1];
                fromTokenList.pop();
                break;
            }
        }
        ownerTokens[_to].push(_tokenId);

        // 清除授权信息
        delete tokenApprovals[_tokenId];
    }

    // 授权指定 NFT 的所有权转移给目标地址
    function approve(address _approved, uint256 _tokenId) public {
        require(_tokenId >= 1 && _tokenId < nextTokenId, "Invalid token ID");
        Token storage token = tokens[_tokenId];
        address owner = token.owner;

        // 判断调用者是否有操作权限
        require(msg.sender == owner, "Not authorized");

        // 更新授权映射
        tokenApprovals[_tokenId] = _approved;
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        return tokens[tokenId].owner;
    }
}
