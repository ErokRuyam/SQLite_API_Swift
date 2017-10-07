//
//  RelationalPersistentStoreProvider.swift
//  CoreClient
//
//  Created by Mayur on 03/10/17.
//  Copyright © 2017 Odocon. All rights reserved.
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

/**
 The protocol lays down the contract for the persistent store providers that intend to base their implementation on
 RDBMS technology.
 */
public protocol RelationalPersistentStoreProvider: PersistentStoreProvider {
    /*
     Executes the given SQL data retrieval query (like, but not limited to SELECT) & returns the status of the operation YES/NO
     i.e. whether the query execution was successful or not.
     Remember the return value doesn't validate the logic of your query or it's validity to obtain the desired result at the logical/semantic
     level in any way. If the method returns NO, it could be due to one more of the following reasons:
     - there was error(s) in the query syntax
     - binded paramaters (number of parameters passed doesn't match with the ones supposed to be bind to the query)
     - runtime error like - integrity constraints were violated
     - or some internal error like the database was found to be locked (probably, owing to unbalanced call to open/close).
     
     Iterating over the result set & retrieving a row:
     -------------------------------------------------
     NOTE: This method in itself doesn't return the result set or cursor to the rows retrieved by executing the submitted query.
     This method just indicates if the query execution was successful or not. If this method returns YES, then one can iterate over the result
     set & retrieve the rows one by one using either of the methods below till they return NIL:
     func getNextRowAsArray() -> Array<Any>
     func getNextRowAsDictionary() -> NSDictionary

     Executing the query & retrieving the entire result set at once:
     ---------------------------------------------------------------
     If one wants to execute the query & obtain the entire result set, then use this method:
     func getResultSetForQuery(_ query: String, withParams params: Array<Any>) -> Array<Any>

     @param query - SQL data retrieval query to execute
     @param params - an array of paramaters to be bound to the query; the parameters are bound based on their position in the query
     i.e. the paramater value for the 1st placeholder appears at 0th index in params array, 2nd at 1st index & so on.
     If the query doesn't have any placeholders & so, doesn't need to bind params, then pass NIL.
     */
    func executeQuery(_ query: String, withParams params: Array<Any>) -> Bool
    
    /*
     Executes the given SQL modification query (UPDATE, INSERT, DELETE, DROP, CREATE etc.) & returns the status of the operation as YES/NO
     i.e. whether the query execution was successful or not. Remember the return value doesn't validate the logic of your query or it's
     validity to obtain the desired result at the logical/semantic level in any way. If the method returns NO, it could be due to one more
     of the following reasons:
     - there was error(s) in the query syntax
     - binded paramaters (number of parameters passed doesn't match with the ones supposed to be bind to the query)
     - runtime error like - integrity constraints were violated
     - or some internal error like the database was found to be locked (probably, owing to unbalanced call to open/close).
     
     @param query - SQL data modification query to execute
     @param params - an array of paramaters to be bound to the query; the parameters are bound based on their position in the query
     i.e. the paramater value for the 1st placeholder appears at 0th index in params array, 2nd at 1st index & so on.
     If the query doesn't have any placeholders & so, doesn't need to bind params, then pass NIL.
     */
    func executeUpdate(_ query: String, withParams params: Array<Any>) -> Bool
    
    //This method returns the row from the result set of most recently executed selection statement as an array.
    func getNextRowAsArray() -> Array<Any>?
    
    /*
     This method returns the row from the result set of recently executed selection/retrieval statement as a dictionary.
     The returned dictionary can be looked up for the column names & corresponding values can be retrieved.
     */
    func getNextRowAsDictionary() -> NSDictionary?
    
    /*
     The method executes the given SQL selection/retrieval query & returns an array of rows, where each row in itself is represented as
     an array. The column values can be retrived using the index and are positioned based on the order of columns specified in the SELECT
     clause.
     For e.g. if query is: SELECT name, address FROM Person WHERE age > 18
     then the each row returned will have value of name column at index 0 & value of address column at index 1.
     If the query is SELECT all i.e.
     SELECT * FROM Person WHERE age > 18
     then the ordering used is the one specified in the CREATE statement for the table.
     
     @param query - SQL data retrieval query to execute
     @param params - an array of paramaters to be bound to the query; the parameters are bound based on their position in the query
     i.e. the paramater value for the 1st placeholder appears at 0th index in params array, 2nd at 1st index & so on.
     If the query doesn't have any placeholders & so, doesn't need to bind params, then pass NIL.
     */
    func getResultSetForQuery(_ query: String, withParams params: Array<Any>) -> Array<Any>?
    
    /*
     Executes the given set of SQL statements as a transaction. The multiple SQL statements/queries shall be separated by new line i.e.
     each query appears on the new row.
     
     Handling the error/failure:
     ---------------------------
     In case there's problem completing the transaction, implementation of this method shall make sure that the transaction is rolled back
     & DB is restored to the previous known state. At no time, shall the DB be left in inconsistent state.
     The exact behaviour of 'Commit' & 'Rollback' depends upon the particular DB. For example, SQLite generally has it's auto-commit
     mode ON & so the rollback is taken care by the SQLite itself. For other's, this might need to be done explicitly.
     
     @param query - one or more SQL queries separated by new line
     @param paramSets - an array of paramaters array to be bound to each query (details as mentioned in executeQuery/executeUpdate methods).
     If the individual query doesn't have any parameters to bound, pass NSNULL; if all the queries are sans any paramater, then pass NIL.
     @param aTarget - reference/pointer to an object whose's selector shall be invoked as a callback to pass the result set of executing the
     queries in the transaction (if the query is selection/retrieval query indeed)
     @param aSelector - the selector to be called on execution of the queries to pass the corresponding result set.
     The supplied selector is invoked for each row in the result set;the selector must have the following signature:
     - 1st parameter contains the index of SQL statement in the transaction
     - 2nd parameter contains the row retrieved from the result set after executing the selection/retrieval statement at corresponding index.
     So, if there are 4 statements on the transaction & the 3rd is selection statement then selector will be invokded with following values:
     1st argument: 2 (as SQL statmenets in the transaction are counted starting from 0,the index of 3rd statement would be 2)
     2nd argument: row which is returned as NSDictionary so the user can look up the column names & retrieve the corresponding values.
     For e.g. the selector might look like
     - (void) handleResultRow:(NSDictionary *) row forQueryInTransactionAtIndex:(NSUInterger) queryIndexInTransaction;
     */
    func executeTransaction(_ query :String, withParamSets paramSets: Array<Any>?, withTarget aTarget: AnyObject?, andSelector aSelector: Selector?) -> Bool
    
    /*
     This method shall return the number of columns pertaining to the result set of the most recently executed query. This method works
     with executeQuery only.If the prior call to the executeQuery method ended up in error, then the value is undefined.
     */
    func getColumnCount() -> Int
    
    /*
     This method shall return the names of columns pertaining to the result set of the most recently executed query. This method works
     with executeQuery only.If the prior call to the executeQuery method ended up in error, then the value is undefined.
     */
    func getColumns() -> Array<String>
    
    /*
     Some DBs provide a way to obtain the Row ID of the last row inserted into the DB.
     For example, in SQLite,this method should be used to get the ROWID of the last inserted row where the ROWID is a column with
     attributes:Primary key+Integer(can be Autoincrement as well but not necessary). This method works with executeUpdate only.
     Simillary, in MySQL,
     If the prior call to executeUdate ended up in error then the value is undefined.
     */
    func getLastInsertRowId() -> Int
}
