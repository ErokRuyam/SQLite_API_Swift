//
//  PersistentStoreProvider.swift
//  CoreClient
//
//  Created by Mayur on 03/10/17.
//  Copyright © 2017 Odocon. All rights reserved.
//

import Foundation

/**
 Lays down the contract for the classes that want to plug in themselves in the Client frameowrk by providing the
 following capabilities:
 - Data persistence
 - Retrieving and/or querying persisted data
 - Adding/Removing/Modifying the data
 
 The internal implementation or the exact technology to be used is specific to the class implementing this protocol.
 One class may opt to conform to this protocol by using relational DB like SQLite and implementation of protocol methods will
 then use SQLite specific semantics/APIs internally.
 Other class may use framework like Core Data internally, still other can choose to have a key-value based storage for implementing
 data persistence & related capabilities. Some classes can even employ proprietary mechanism for persisting/querying/maintaining
 the data.
 As long as the provider class conforms to this protocol, it can be used within the framework; internal implementation is
 prerogative of the provider.
 
 Client framwork provides the concrete implementation for the RDBMS based persistent data provider using SQLite.
 */
public protocol PersistentStoreProvider {
    /*
     This method shall open the persistent store & initialize it's internal state (if any) so as to prepare itself & be ready
     to serve further API calls. The below sequence will be used while using the persistent store in general -
     1. Open the store
     2. Perform one or more operations like add/update/get/remove
     3. Close the store
     
     One must make sure that each open call is matched by it's corresponding close call; else the DB might end up in inconsistent
     state & behaviour would be unknown.
     
     @param storeNameOrFilepath - the name of the persistent store or it's path on file system.
     @param createIfNeeded - the flag to indicate whether the new store shall be created if there doesn't exist one
     with a given name at given location.
     */
    func openStoreCreateIfNeeded(_ storeNameOrFilepath: String, createIfNeeded: Bool)
    
    /*
     This method shall close the store & invalidate/cleanup all of it's internal state &/or data structures.
     It should make sure that the connection to the store doesn't remain open anymore after call to this method.
     */
    func closeStore()
}

extension PersistentStoreProvider {
    public func openStoreCreateIfNeeded(_ storeNameOrFilepath: String, createIfNeeded: Bool) {
        //Default implementation does nothing
    }
    
    public func closeStore() {
        //Default implementation does nothing
    }
}
