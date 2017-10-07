//
//  SQLiteManager.swift
//
//  Created by Mayur on 04/10/17.
//  Copyright © 2017 Mayur. All rights reserved.
//

/*
MIT License

Copyright (c) 2017 Mayur Kore

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/


import Foundation
import SQLite3

let SQLITE_STATIC = unsafeBitCast(0, to: sqlite3_destructor_type.self)
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
let SQLITE_ERROR_DOMAIN = "SQLiteErrorDomain"

//TODO: The class needs to conform to the RelationalPersistentStoreProvider protocol currently in the  codebase
//Need to migrate frameowrk to common repository to be used by both - Vaultize, vDRM & any other app that comes down the line.

public enum SQLiteErrorCode: Int {
    case sqliteError ///Generic error
    case sqliteErrorOpen ///Error opening an SQLite DB.
    case sqliteErrorClose ///Error closing an SQLite DB.
    case sqliteErrorBind ///Error binding params to the prepared statement;insufficient parameters can be one of it.
    case sqliteErrorPrepare ///Error preparing the statement.
    case sqliteErrorTransaction ///Error executing the transaction.
}

//TODO: check if Foreign Key constraints setting is on/off. Shall we enforce the FK constraints?
open class SQLiteManager: RelationalPersistentStoreProvider {
    
    fileprivate var db: OpaquePointer?
    fileprivate var currentColumnCount: Int = 0 //The number of columns in the result set of the currently executed query.
    fileprivate var statement: OpaquePointer? //The prepared statment corresponding to the currently executed SQL query.
    public var dbError: NSError?
    
    //Prepare an error object at a single place to be returned to the client of this class.
    func prepareError() {
        dbError = NSError.init(domain: SQLITE_ERROR_DOMAIN, code: sqlite3_errcode(db!).hashValue, userInfo: ["errorMessage" : "\(sqlite3_errmsg(db))"])
        print("Error = \(dbError!)")
    }
    
    public func openStoreCreateIfNeeded(_ storeNameOrFilepath: String, createIfNeeded: Bool) {
        var status: Int32
        dbError = nil
        if createIfNeeded {
            status = sqlite3_open_v2(storeNameOrFilepath.cString(using: String.Encoding.utf8)!, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil)
        } else {
            //By default, sqlite_open is has create+read/write behaviour.
            status = sqlite3_open(storeNameOrFilepath.cString(using: String.Encoding.utf8)!, &db)
        }
        
        if status != SQLITE_OK {
            //Even if some error occures while opening the DB,SQLite returns handle to the sqlite3 structure.
            //So it's imperative to clear the database handle & related resources.
            sqlite3_close(db!)
            self.prepareError()
        }
    }
    
    //This method clears all the bindings for the last prepared statement & finalizes it(i.e clears the memory corresponding to the prepared statement).
    func clearState() {
        currentColumnCount = 0
        if statement != nil {
            sqlite3_reset(statement!)//if the previous prepared statement had any params binded then clear it.
            sqlite3_finalize(statement!)
        }
        statement = nil
        dbError = nil
    }
    
    public func closeStore() {
        self.clearState()
        sqlite3_close(db!)
        /*
         int status=sqlite3_close(db);
         [self prepareError];
         */
    }
    
    //This method returns the names of columns pertaining to the result set of the most recently executed query.
    //If the prior call to the method executeQuery false/no then the value is undefined.
    //This methosd works with executeQuery only.
    public func getColumns() -> Array<String> {
        var columns = Array<String>()
        columns.reserveCapacity(currentColumnCount)
        for i: Int32 in 0 ..< Int32(currentColumnCount) {
            columns.append("\(sqlite3_column_name(statement!, Int32(i)))")
        }
        return columns
    }
    
    //This method returns the number of columns pertaining to the result set of the most recently executed query.
    //If the prior call to the method executeQuery false/no or then the value is undefined.
    //This methosd works with executeQuery only.
    public func getColumnCount() -> Int {
        return currentColumnCount
    }
    
    //This method should be used to get the ROWID of the last inserted row where the ROWID is a column with attributes:Primary key+Integer(
    //can be Autoincrement as well but not necessary).
    //If the prior call to executeUdate returns false/no then the retunred value is undefined.
    public func getLastInsertRowId() -> Int {
        return Int(sqlite3_last_insert_rowid(db!))
    }
    
    //This method should be used for performing the data retrieval with SELECT clause.
    //If there are any parameters in the query that are to be bound, then those are passed as an array. The 0th element in array will
    //bind to 1st parameter in the query & so on. If the query has no parameters then pass nil for params.
    public func executeQuery(_ query: String, withParams params: [Any]) -> Bool {
        if statement != nil {
            //Suppose for the previous query/update, the prepared statement was not reclaimed/mem-cleared
            //then first clear the memory corresponding to this statement.This might happen if not all the
            //records from the result set were iterated over. In that case statement remained valid in memory.
            self.clearState()
        }
        
        var didBind = true
        let cQuery = query.cString(using: String.Encoding.utf8)
        var status = sqlite3_prepare_v2(db!,cQuery!, -1, &statement, nil)
        
        //If there's an error compiling/preparing the statement then it's set to NULL.
        if status == SQLITE_OK && statement != nil {
            print("executeQuery Bind params count: \(sqlite3_bind_parameter_count(statement))")
            let numParams: Int = Int(sqlite3_bind_parameter_count(statement!))
            
            if numParams > 0 && params.count != numParams {
                didBind = false
                dbError = NSError.init(domain: SQLITE_ERROR_DOMAIN, code: SQLiteErrorCode.sqliteErrorBind.rawValue, userInfo: nil)
            } else if numParams > 0 {
                for i: Int in 0 ..< numParams {
                    if params[i] is NSNumber {
                        if let value = params[i] as? Double {
                            status = sqlite3_bind_double(statement!, Int32(i + 1), CDouble(value))
                        } else if let value = params[i] as? Float {
                            status = sqlite3_bind_double(statement!, Int32(i + 1), CDouble(value))
                        } else if let value = params[i] as? Int {
                            status = sqlite3_bind_int(statement!, Int32(i + 1), Int32(value))
                        } else if let value = params[i] as? UInt {
                            status = sqlite3_bind_int64(statement!, Int32(i + 1), Int64(value))
                        } else if let value = params[i] as? CLong {
                            status = sqlite3_bind_int64(statement!, Int32(i + 1), Int64(value))
                        } else if let value = params[i] as? CLongLong {
                            status = sqlite3_bind_int64(statement!, Int32(i + 1), Int64(value))
                        } else {
                            //Default: If nothing above matches, bind to int.
                            //E.g. like short, unsigned short, unsigned long etc.
                            status = sqlite3_bind_int(statement!, Int32(i + 1), ((params[i] as! NSNumber).int32Value))
                        }
                    } else if let string = params[i] as? String {
                        status = sqlite3_bind_text(statement!, Int32(i + 1), string, -1, SQLITE_TRANSIENT)
                    } else if let data = params[i] as? NSData {
                        status = sqlite3_bind_blob(statement!, Int32(i + 1), data.bytes, CInt(data.length), SQLITE_TRANSIENT)
                    } else {
                        status = sqlite3_bind_null(statement!, Int32(i + 1))
                    }
                    
                    if status != SQLITE_OK {
                        didBind = false
                        dbError = NSError.init(domain: SQLITE_ERROR_DOMAIN, code: SQLiteErrorCode.sqliteErrorBind.rawValue, userInfo: nil)
                        //NSLog(@"executeQuery Error: Binding the parameter at: %d",i);
                        break
                    }
                }
            }
        }
        
        if status == SQLITE_OK && statement != nil && didBind {
            currentColumnCount = Int(sqlite3_column_count(statement!))
            return true
        }
        
        dbError = NSError.init(domain: SQLITE_ERROR_DOMAIN, code: SQLiteErrorCode.sqliteErrorPrepare.rawValue, userInfo: nil)
        print("Error:executeQuery preparing the statement: \(query) Error: \(sqlite3_errmsg(db!))")
        return false
    }
    
    //This method shoud be used for performing changes to the DB with INSERT,UPDATE,DELETE clause.
    //By default the Auto-commit mode is enabled for SQLite.
    //W.r.t. executing the updates, the INSERTS are automic by default & are executed as transactions as mentioned in docs:
    //http://sqlite.org/faq.html#q19
    //http://sqlite.org/atomiccommit.html
    //This update may be executed as a transaction (or as a part of transaction) or as single/stand-alone SQL statement.
    //If it's standalone statement & error occures while executing the statement then following rule applies:
    //1.If auto-commit mode of SQLite is enabled(which is the default case), the rollbacking the transaction is taken care by SQLite iteself.
    //2.If auto-commit is disabled, this method explicitely rollbacks the transaction.
    //If there are any parameters in the query that are to be bound, then those are passed as an array. The 0th element in array will
    //bind to 1st parameter in the query & so on. If the query has no parameters then pass nil for params.
    public func executeUpdate(_ query: String, withParams params: Array<Any>) -> Bool {
        if statement != nil {
            //Suppose for the previous query/update, the prepared statement was not reclaimed/mem-cleared
            //then first clear the memory corresponding to this statement.This might happen if not all the
            //records from the result set were interated over. In that statement remained valid in memory.
            self.clearState()
        }
        // End
        
        var didBind = true
        let cQuery = query.cString(using: String.Encoding(rawValue: String.Encoding.utf8.rawValue))
        var status = sqlite3_prepare_v2(db!, cQuery,-1, &statement, nil)
        
        if status == SQLITE_OK && statement  != nil {
            let numParams: Int = Int(sqlite3_bind_parameter_count(statement!))
            
            if numParams > 0 && params.count != numParams {
                didBind = false
                dbError = NSError.init(domain: SQLITE_ERROR_DOMAIN, code: SQLiteErrorCode.sqliteErrorBind.rawValue, userInfo: nil)
            } else if numParams > 0 {
                for i in 0 ..< numParams {
                    if params[i] is NSNumber {
                        if let value = params[i] as? Double {
                            status = sqlite3_bind_double(statement!, Int32(i + 1), CDouble(value))
                        } else if let value = params[i] as? Float {
                            status = sqlite3_bind_double(statement!, Int32(i + 1), CDouble(value))
                        } else if let value = params[i] as? Int {
                            status = sqlite3_bind_int(statement!, Int32(i + 1), Int32(value))
                        } else if let value = params[i] as? UInt {
                            status = sqlite3_bind_int64(statement!, Int32(i + 1), Int64(value))
                        } else if let value = params[i] as? CLong {
                            status = sqlite3_bind_int64(statement!, Int32(i + 1), Int64(value))
                        } else if let value = params[i] as? CLongLong {
                            status = sqlite3_bind_int64(statement!, Int32(i + 1), Int64(value))
                        } else {
                            //Default: If nothing above matches, bind to int.
                            //E.g. like short, unsigned short, unsigned long etc.
                            status = sqlite3_bind_int(statement!, Int32(i + 1), ((params[i] as! NSNumber).int32Value))
                        }
                    } else if let string = params[i] as? String {
                        status = sqlite3_bind_text(statement!, Int32(i + 1), string, -1, SQLITE_TRANSIENT)
                    } else if let data = params[i] as? NSData {
                        status = sqlite3_bind_blob(statement!, Int32(i + 1), data.bytes, CInt(data.length), SQLITE_TRANSIENT)
                    } else {
                        status = sqlite3_bind_null(statement!, Int32(i + 1))
                    }
                    
                    if status != SQLITE_OK {
                        didBind = false
                        dbError = NSError.init(domain: SQLITE_ERROR_DOMAIN, code: SQLiteErrorCode.sqliteErrorBind.rawValue, userInfo: nil)
                        break
                    }
                }
                
            }//end of if numParams>0
            
            if didBind {
                //Status is SQLITE_DONE on successful execution.
                if let _statement = statement {
                    status = sqlite3_step(_statement)
                }
            }
        }
        
        if status == SQLITE_DONE && didBind && statement != nil {//Possibly needs to re-look at this flag checking.
            return true
        } else if sqlite3_get_autocommit(db!) == 0  {
            //When the Auto-commit mode is On,there's no need to manually/explicitly rollback the transaction as the SQLite takes
            //the responsibility of doing the rollback.
            print("Error:executeUpdate Auto-commit off;Rollbacking the transaction \nError details: \(sqlite3_errmsg(db)) for query:\(query)")
            sqlite3_exec(db!, "ROLLBACK", nil, nil, nil);
            dbError = NSError.init(domain: SQLITE_ERROR_DOMAIN, code: SQLiteErrorCode.sqliteErrorTransaction.rawValue, userInfo: nil)
        } else {
            dbError = NSError.init(domain: SQLITE_ERROR_DOMAIN, code: SQLiteErrorCode.sqliteErrorPrepare.rawValue, userInfo: nil)
        }
        print("Error:executeUpdate \nError details: \(sqlite3_errmsg(db!)) for query:\(query.debugDescription) status = \(status)")
        return false
    }
    
    //This method should be used to execute the multiple SQL statements as the transaction.
    //It internally calls executeQuery & executeUpdate for exceuting the statements.In case the transaction aborts & couldn't be run
    //till completion then the following rules apply:
    //1.If auto-commit mode of SQLite is enabled(which is the default case), the rollbacking the transaction is taken care by SQLite iteself.
    //2.If auto-commit is disabled, this method explicitely rollbacks the transaction.
    //As SELECT statements don't perform changes on the DB,there is no need to rollback them.
    //For each SELECT statement, this method invokes the supplied selector for each row in the result set;the selector must have the
    //following parameters:
    //1st parameter contains the index of SQL statement in the transaction
    //2nd parameter contains the row retrieved from the result set after executing the SELECT statement at corresponding index.
    //So if there are 4 statements on the transaction & the 3rd is SELECT statement then parametrs will have following values in them:
    //1st: 2 (as SQL statmenets in the transaction are counted starting from 0,the index of 3rd statement would be 2)
    //2nd argument: row which is returned as NSDictionary so the user can look up the column names & retrieve the corresponding values.
    //params is the array of the arrays that supply the values to bind to the parameters for the each statement in the transaction.
    //If the statement has no parameters add nil to the array. If all the statements in the transaction are sans parameters then pass
    //nil for the paramSets.
    public func executeTransaction(_ query: String, withParamSets paramSets: Array<Any>?, withTarget aTarget: AnyObject?, andSelector aSelector: Selector?) -> Bool {
        var status = false

        let temp = query.components(separatedBy: "\n")
        var multipleQueries = Array<Any>()

        if (temp.count > 0) {
            multipleQueries.append(temp)
        }
        if sqlite3_get_autocommit(db!) == 0 {
            multipleQueries.insert("BEGIN TRANSACTION", at: 0)
            multipleQueries.append("COMMIT")
        }

        for i in 0 ..< multipleQueries.count {
            var isSelectQuery = false
            var params = paramSets != nil ? paramSets?[i] : nil
            params = (params == nil) ? nil : params

            if ((multipleQueries[i] as? String)?.hasPrefix("SELECT"))! {
                isSelectQuery = true
                status = self.executeQuery(multipleQueries[i] as! String, withParams:params as! [Any])
            } else {
                status = self.executeUpdate(multipleQueries[i] as! String, withParams:params as! Array<Any>)
            }
            if (!status) {
                print("Error:executeTransaction \nError Details:\(sqlite3_errmsg(db)) for query:\(multipleQueries[i])")
                if sqlite3_get_autocommit(db) == 0 {
                    print("Error:executeTransaction Auto-commit off;Rollbacking the transaction \nError details: \(sqlite3_errmsg(db)) for query:\(query)")
                    sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                }
                break;
            } else if isSelectQuery && aTarget != nil && aSelector != nil {
                while let row = self.getNextRowAsDictionary() {
                    _ = aTarget?.perform(aSelector, with: NSNumber.init(value: i), with: row)
                }
            }
        }
        
        return status
    }
    
    //This method returns the row from the result set of recently executed SELECT statement as an array.
    public func getNextRowAsArray() -> Array<Any>? {
        var row: Array<Any>?
        
        if sqlite3_step(statement!) == SQLITE_ROW {
            row = Array<Any>()
            row!.reserveCapacity(currentColumnCount)
            for i: Int32 in 0 ..< Int32(currentColumnCount) {
                let dataType = sqlite3_column_type(statement!, i)
                if dataType == SQLITE_INTEGER {
                    row!.append(NSNumber.init(value: sqlite3_column_int(statement!, i) as Int32))
                } else if dataType == SQLITE_FLOAT {
                    row!.append(NSNumber.init(value: sqlite3_column_double(statement!, i) as Double))
                } else if dataType == SQLITE_TEXT {
                    row!.append(String.init(cString: sqlite3_column_text(statement!, i)))
                } else if dataType == SQLITE_BLOB {
                    let blobData = Data.init(bytes: sqlite3_column_blob(statement!, i), count: Int(sqlite3_column_bytes(statement!, i)))
                    row!.append(blobData)
                } else if dataType == SQLITE_NULL {
                    row!.append("") //or add "" string instead of null.
                }
            }
        } else {
            //Whatever might be the reason,SQLITE_DONE or SQLITE_ERROR(or it's variant) do release the memory for the prepared statement.
            print("Clearing the Prepared Statement...")
            self.clearState()
        }
        
        return row
    }
    
    //This method returns the row from the result set of recently executed SELECT statement as a dictionary.
    //The returned dictionary can be looked up for the column names & corresponding values can be retrieved.
    public func getNextRowAsDictionary() -> NSDictionary? {
        var row: NSMutableDictionary?
        
        if sqlite3_step(statement) == SQLITE_ROW {
            row = NSMutableDictionary.init(capacity: currentColumnCount)
            for i: Int32 in 0 ..< Int32(currentColumnCount) {
                let dataType = sqlite3_column_type(statement!, i)
                if dataType == SQLITE_INTEGER {
                    row![String.init(cString: sqlite3_column_name(statement!, i))] = NSNumber.init(value: sqlite3_column_int(statement!, i) as Int32)
                } else if dataType == SQLITE_FLOAT {
                    row![String.init(cString: sqlite3_column_name(statement!, i))] = NSNumber.init(value: sqlite3_column_double(statement!, i) as Double)
                } else if dataType == SQLITE_TEXT {
                    row![String.init(cString: sqlite3_column_name(statement!, i))] = String.init(cString: sqlite3_column_text(statement!, i))
                } else if dataType == SQLITE_BLOB {
                    row![String.init(cString: sqlite3_column_name(statement!, i))] = Data.init(bytes: sqlite3_column_blob(statement!,i), count: Int(sqlite3_column_bytes(statement!,i)))
                } else if dataType == SQLITE_NULL {
                    row![String.init(cString: sqlite3_column_name(statement!, i))] = nil
                }
            }
        } else{
            //Whatever might be the reason,SQLITE_DONE or SQLITE_ERROR(or it's variant) do release the memory for the prepared statement.
            print("Clearing the Prepared Statement...")
            self.clearState()
        }
        
        return row
    }
    
    public func getResultSetForQuery(_ query: String, withParams params: Array<Any>) -> Array<Any>? {
        let status = self.executeQuery(query, withParams:params)
        var resultSet: Array<Any>?
        
        if status {
            resultSet = Array<Any>()
            var row: Array<Any>? = getNextRowAsArray()
            while row != nil {
                resultSet!.append(row!)
                row = getNextRowAsArray()
            }
        }
        return resultSet
    }
}
