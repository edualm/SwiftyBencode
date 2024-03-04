//
//  Helpers.swift
//  SwiftyBencode
//
//  Created by Arnaud Dorgans on 17/09/2018.
//

import Foundation

extension ArraySlice where Element == UInt8 {
    
    var bytes: [UInt8] {
        return Array(self)
    }
}

extension Array where Element == UInt8 {
    
    var data: Data {
        return Data(self)
    }
}

extension Data {
    
    var bytes: [UInt8] {
        return [UInt8](self)
    }
}

protocol OptionalType {
    associatedtype W
    var optional: W? { get }
}

extension Optional: OptionalType {
    typealias W = Wrapped
    var optional: W? { return self }
}

extension Array where Element: OptionalType {
    
    func unwrap() -> [Element.W] {
        return self.map { $0.optional }.filter { $0 != nil }.map { $0! }
    }
}
