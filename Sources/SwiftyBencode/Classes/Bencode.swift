//
//  Bencode.swift
//  SwiftyBencode
//
//  Created by Arnaud Dorgans on 16/04/2018.
//  Copyright © 2018 Arnaud Dorgans. All rights reserved.
//

import CryptoSwift
import Foundation

public typealias Byte = UInt8
public typealias Bytes = [Byte]

public protocol BencodeProtocol: Sequence, CustomStringConvertible {
    
    var dictionary: [String: Bencode]? { get }
    var array: [Bencode]? { get }
    
    init?(data: Data)
    init?(url: URL)
    init?(bytes: Bytes)
}

extension BencodeProtocol {

    public func makeIterator() -> DictionaryIterator<AnyHashable, Bencode> {
        if let dictionary = self.dictionary {
            return (dictionary as [AnyHashable: Bencode]).makeIterator()
        }
        if let array = self.array {
            return (0..<array.count).reduce([:]) { dictionary, index in
                var dictionary = dictionary
                dictionary[index] = array[index]
                return dictionary
            }.makeIterator()
        }
        return [:].makeIterator()
    }
    
    public subscript(_ key: AnyHashable) -> Bencode? {
        if let key = key as? String {
            return self.dictionary?[key]
        }
        if let index = key as? Int {
            return self.array?[index]
        }
        return nil
    }
    
    public init?(data: Data) {
        self.init(bytes: data.bytes)
    }
    
    public init?(url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        self.init(data: data)
    }
}

public struct TorrentFile {
    
    public let path: [String]
    public let length: Int
    public let range: CountableRange<Int>
    
    public var start: Int {
        return range.lowerBound
    }
    
    public var end: Int {
        return range.upperBound
    }
    
    public init(path: [String], length: Int, start: Int) {
        self.path = path
        self.length = length
        self.range = start..<(start + length)
    }
}

public struct Torrent: BencodeProtocol {
    
    public let infoHash: String
    public let name: String?
    public let filename: String?
    public let announce: URL
    public let announceList: [URL]
    public let files: [TorrentFile]
    public let length: Int
    public let pieceLength: Int!
    public let pieces: [String]!
    public let comment: String?
    public let createdBy: String?
    public let date: Date?
    
    private let bencode: Bencode
    
    public var description: String {
        return bencode.description
    }
    
    public var dictionary: [String : Bencode]? {
        return bencode.dictionary
    }
    
    public var array: [Bencode]? {
        return bencode.array
    }
    
    public init?(bytes: Bytes) {
        guard let bencode = Bencode(bytes: bytes) else {
            return nil
        }
        self.bencode = bencode
        let torrentName = bencode["info"]?["name"]?.string
        let pieceHashes: [String]? = {
            return bencode["info"]?["pieces"]?.bytes.flatMap { bytes in
                let size = 20
                return (0..<(bytes.count / size)).map { index in
                    let start = index * size
                    let end = start + size
                    return bytes[start..<end].bytes.toHexString()
                }
            }
        }()
        let files: [TorrentFile] = {
            let length = bencode["info"]?["length"]?.integer
            return bencode["info"]?["files"]?.map { $0.value }.reduce(([], 0)) { data, item -> (files: [TorrentFile], index: Int) in
                var data = data
                if let path = item["path"]?.map({ $0.value.string }).unwrap(),
                    let length = item["length"]?.integer {
                    data.files.append(TorrentFile(path: path, length: length, start: data.index))
                    data.index += length
                }
                return data
                }.files ?? torrentName.flatMap { name in length.flatMap { [TorrentFile(path: [name], length: $0, start: 0)] } } ?? []
        }()
        guard let infoHash = bencode["info"]?.fullBytes.sha1().toHexString(),
            let announce = bencode["announce"]?.string.flatMap({ URL(string: $0) }),
            !files.isEmpty,
            let pieceLength = bencode["info"]?["piece length"]?.integer,
            let pieces = pieceHashes, !pieces.isEmpty else {
            return nil
        }
        self.infoHash = infoHash
        self.name = torrentName
        self.filename = bencode["info"]?["filename"]?.string
        self.date = bencode["creation date"]?.integer.flatMap { Date(timeIntervalSince1970: TimeInterval($0)) }
        self.announce = announce
        self.announceList = {
            func urls(item: Bencode) -> [URL] {
                if let string = item.string {
                    return [URL(string: string)].unwrap()
                }
                return item.flatMap { urls(item: $0.value) }
            }
            return bencode["announce-list"].flatMap { urls(item: $0) } ?? [announce]
        }()
        self.files = files
        self.length = files.map { $0.length }.reduce(0, +)
        self.comment = bencode["comment"]?.string
        self.pieceLength = pieceLength
        self.createdBy = bencode["info"]?["created by"]?.string
        self.pieces = pieces
    }
}

extension Torrent: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.infoHash.hashValue)
    }
    
    public static func == (lhs: Torrent, rhs: Torrent) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }    
}

enum BencodeSeparator: Byte {
    case integer = 0x69
    case dictionary = 0x64
    case array = 0x6c
    case end = 0x65
    case colon = 0x3a
}

public enum BencodeType {
    case dictionary
    case array
    case integer
    case bytes
}

typealias BencodeResult = (bencode: Bencode, end: Data.Index)

public struct Bencode: BencodeProtocol {
    
    public let type: BencodeType
    public let fullBytes: [UInt8]
    private let value: Any
    
    public var description: String {
        switch type {
        case .array:
            return String(describing: self.array ?? [])
        case .dictionary:
            return String(describing: self.dictionary ?? [:])
        case .integer:
            if let integer = integer {
                return String(integer)
            }
        case .bytes:
            if let string = string {
                return string
            }
        }
        return String(describing: Data(fullBytes))
    }
    
    public func string(encoding: String.Encoding) -> String? {
        guard let bytes = value as? [UInt8] else {
            return nil
        }
        return String(bytes: bytes, encoding: encoding)
    }
    
    public var string: String? {
        switch type {
        case .bytes:
            return self.string(encoding: .utf8)
        default:
            return nil
        }
    }
    
    public var integer: Int? {
        switch type {
        case .integer:
            return value as? Int
        default:
            return nil
        }
    }
    
    public var bytes: [UInt8]? {
        switch type {
        case .bytes:
            return value as? [UInt8]
        default:
            return nil
        }
    }
    
    public var dictionary: [String: Bencode]? {
        switch type {
        case .dictionary:
            return value as? [String: Bencode]
        default:
            return nil
        }
    }
    
    public var array: [Bencode]? {
        switch type {
        case .array:
            return value as? [Bencode]
        default:
            return nil
        }
    }
    
    public subscript(_ key: String) -> Bencode? {
        return dictionary?[key]
    }
    
    public subscript(_ index: Int) -> Bencode? {
        return array?[index]
    }
    
    private init(type: BencodeType, fullBytes: [UInt8], value: Any) {
        self.type = type
        self.fullBytes = fullBytes
        self.value = value
    }
    
    public init?(bytes: Bytes) {
        guard let bencode = Bencode.parse(bytes: bytes)?.bencode else {
            return nil
        }
        self = bencode
    }
    
    private static func ascii(bytes: Bytes) -> String? {
        return String(bytes: bytes, encoding: .ascii)
    }
    
    private static func firstByte(bytes: Bytes, range: Range<Data.Index>? = nil) -> Byte? {
        guard !bytes.isEmpty else {
            return nil
        }
        if let range = range, range.upperBound > bytes.endIndex {
            return nil
        }
        return bytes[range?.lowerBound ?? bytes.startIndex]
    }
    
    private static func parse(bytes: Bytes, range: Range<Data.Index>? = nil) -> BencodeResult? {
        guard let firstByte = self.firstByte(bytes: bytes, range: range) else {
            return nil
        }
        switch firstByte {
        case BencodeSeparator.end.rawValue:
            return nil
        case BencodeSeparator.integer.rawValue:
            return parseInteger(bytes: bytes, range: range)
        case BencodeSeparator.array.rawValue:
            return parseArray(bytes: bytes, range: range)
        case BencodeSeparator.dictionary.rawValue:
            return parseDictionary(bytes: bytes, range: range)
        default:
            return parseBytes(bytes: bytes, range: range)
        }
    }
    
    private static func range(of separator: BencodeSeparator, bytes: Bytes, range: Range<Data.Index>? = nil) -> Range<Data.Index>? {
        let data = bytes.data
        return data.range(of: [separator.rawValue].data, options: [], in: range)
    }
    
    private static func range(from range: Range<Data.Index>? = nil, start: Data.Index? = nil, end: Data.Index? = nil, bytes: Bytes) -> Range<Data.Index> {
        let start: Data.Index = [range?.lowerBound, start, bytes.startIndex].unwrap().sorted().reversed()[0]
        let end: Data.Index = [range?.upperBound, end, bytes.index(before: bytes.endIndex)].unwrap().sorted()[0]
        return start..<end
    }
    
    private static func parseInteger(bytes: Bytes, range: Range<Data.Index>? = nil) -> BencodeResult? {
        guard let start = self.range(of: .integer, bytes: bytes, range: range),
            let end = self.range(of: .end, bytes: bytes, range: self.range(from: range, start: start.upperBound, bytes: bytes)),
            let integer = self.ascii(bytes: bytes[start.upperBound..<end.lowerBound].bytes).flatMap({ Int($0) }) else {
                return nil
        }
        return BencodeResult(bencode: Bencode(type: .integer, fullBytes: bytes[start.lowerBound..<end.upperBound].bytes, value: integer),
                             end: end.upperBound)
    }
    
    private static func parseBytes(bytes: Bytes, range: Range<Data.Index>? = nil) -> BencodeResult? {
        let start = self.range(from: range, bytes: bytes)
        guard let colon = self.range(of: .colon, bytes: bytes, range: range),
            let count = self.ascii(bytes: bytes[start.lowerBound..<colon.lowerBound].bytes).flatMap({ Int($0) }) else {
            return nil
        }
        let end = self.range(from: range, start: colon.upperBound, end: colon.upperBound.advanced(by: count), bytes: bytes)
        return BencodeResult(bencode: Bencode(type: .bytes,
                                            fullBytes: bytes[start.lowerBound..<end.upperBound].bytes,
                                            value: bytes[end].bytes),
                             end: end.upperBound)
    }
    
    private static func parseArray(bytes: Bytes, range: Range<Data.Index>? = nil, type: BencodeSeparator = .array) -> BencodeResult? {
        guard let start = self.range(of: type, bytes: bytes, range: range) else {
            return nil
        }
        var lastEnd = start.upperBound
        var items = [Bencode]()
        while let nextResult = self.parse(bytes: bytes, range: self.range(from: range, start: lastEnd, bytes: bytes)) {
            lastEnd = nextResult.end
            items.append(nextResult.bencode)
        }
        lastEnd = self.range(from: range, end: bytes.index(after: lastEnd), bytes: bytes).upperBound
        return BencodeResult(bencode: Bencode(type: .array, fullBytes: bytes[start.lowerBound..<lastEnd].bytes, value: items),
                             end: lastEnd)
    }
    
    private static func parseDictionary(bytes: Bytes, range: Range<Data.Index>? = nil) -> BencodeResult? {
        guard let result = parseArray(bytes: bytes, range: range, type: .dictionary) else {
            return nil
        }
        var array = result.bencode.array ?? []
        while array.count % 2 != 0 { array.removeLast() }
        let dictionary = (0..<array.count / 2).map { $0 * 2 }.reduce([:], { dictionary, index -> [String: Bencode] in
            var dictionary = dictionary
            let key = array[index]
            let value = array[index + 1]
            if let key = key.string {
                dictionary[key] = value
            }
            return dictionary
        })
        return BencodeResult(bencode: Bencode(type: .dictionary, fullBytes: result.bencode.fullBytes, value: dictionary),
                             end: result.end)
        
    }
}
