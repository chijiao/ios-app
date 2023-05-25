//
//  KemHelper.swift
//  IVPN iOS app
//  https://github.com/ivpn/ios-app
//
//  Created by Juraj Hilje on 2023-05-25.
//  Copyright (c) 2023 Privatus Limited.
//
//  This file is part of the IVPN iOS app.
//
//  The IVPN iOS app is free software: you can redistribute it and/or
//  modify it under the terms of the GNU General Public License as published by the Free
//  Software Foundation, either version 3 of the License, or (at your option) any later version.
//
//  The IVPN iOS app is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
//  or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
//  details.
//
//  You should have received a copy of the GNU General Public License
//  along with the IVPN iOS app. If not, see <https://www.gnu.org/licenses/>.
//

import Foundation
import CryptoKit

enum KemAlgorithm: String, CaseIterable {
    case Kyber1024 = "Kyber1024"
    case ClassicMcEliece348864 = "Classic-McEliece-348864"
}

enum KemHelperError: Error {
    case initError
    case generateKeysError
}

struct KemHelper {
    
    // MARK: - Properties -
    
    private var algorithms = [KemAlgorithm]()
    private var privateKeys = [String]() // base64
    private var publicKeys = [String]() // base64
    private var ciphers = [String]() // base64
    private var secrets = [String]() // base64 (decoded ciphers)
    
    // MARK: - Initialize -
    
    init(algorithms: [KemAlgorithm] = KemAlgorithm.allCases) throws {
        self.algorithms = algorithms
        guard !algorithms.isEmpty else {
            throw KemHelperError.initError
        }
        
        generateKeys()
        guard !privateKeys.isEmpty, !publicKeys.isEmpty else {
            throw KemHelperError.generateKeysError
        }
    }
    
    // MARK: - Methods -
    
    func getPublicKey(algorithm: KemAlgorithm) -> String {
        let index = getIndex(algorithm: algorithm)
        return publicKeys[getIndex(algorithm: algorithm)]
    }
    
    mutating func setCipher(algorithm: KemAlgorithm, cipher: String) {
        let index = getIndex(algorithm: algorithm)
        ciphers[index] = cipher
    }
    
    mutating func calculatePresharedKey() -> String? {
        decodeCiphers(ciphers: ciphers)
        return hashSecrets(secrets: secrets)
    }
    
    // MARK: - Private Methods -
    
    private mutating func generateKeys() {
        (self.privateKeys, self.publicKeys) = generateKeysMulti(algorithms: algorithms)
    }
    
    private mutating func decodeCiphers(ciphers: [String]) {
        secrets = decodeCipherMulti(algorithms: algorithms, privateKeys: privateKeys, ciphers: ciphers)
    }
    
    private func generateKeys(algorithm: KemAlgorithm) -> (String, String) {
        var kem = algorithm == .Kyber1024 ? OQS_KEM_kyber_1024_new() : OQS_KEM_classic_mceliece_348864_new()
        let publicKey = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(kem?.pointee.length_public_key ?? 0))
        let secretKey = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(kem?.pointee.length_secret_key ?? 0))
        OQS_KEM_keypair(kem, publicKey, secretKey)
        
        let publicKeyData = Data(bytes: publicKey, count: Int(kem?.pointee.length_public_key ?? 0))
        let secretKeyData = Data(bytes: secretKey, count: Int(kem?.pointee.length_secret_key ?? 0))
        
        OQS_KEM_free(kem)
        publicKey.deallocate()
        secretKey.deallocate()

        return (publicKeyData.base64EncodedString(), secretKeyData.base64EncodedString())
    }
    
    private mutating func generateKeysMulti(algorithms: [KemAlgorithm]) -> ([String], [String]) {
        var privateKeys = [String]()
        var publicKeys = [String]()
        for algo in algorithms {
            let (priv, pub) = generateKeys(algorithm: algo)
            privateKeys.append(priv)
            publicKeys.append(pub)
        }
        
        return (privateKeys, publicKeys)
    }
    
    private func decodeCipher(algorithm: KemAlgorithm, privateKeyBase64: String, cipherBase64: String) -> String {
        // TODO: Implement decodeCipher()
        return ""
    }
    
    private mutating func decodeCipherMulti(algorithms: [KemAlgorithm], privateKeys: [String], ciphers: [String]) -> [String] {
        for (index, algo) in algorithms.enumerated() {
            let secret = decodeCipher(algorithm: algo, privateKeyBase64: privateKeys[index], cipherBase64: ciphers[index])
            secrets.append(secret)
        }
        
        return secrets
    }
    
    private func getIndex(algorithm: KemAlgorithm) -> Int {
        for (index, algo) in algorithms.enumerated() {
            if algo == algorithm {
                return index
            }
        }
        
        return -1
    }
    
    func hashSecrets(secrets: [String]) -> String? {
        var hasher = SHA256()
        for secret in secrets {
            guard let sDecoded = Data(base64Encoded: secret) else {
                return nil
            }
            hasher.update(data: sDecoded)
        }
        let hash = hasher.finalize()
        return Data(hasher.finalize()).base64EncodedString()
    }
    
}
