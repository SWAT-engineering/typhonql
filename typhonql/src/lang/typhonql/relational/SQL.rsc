/********************************************************************************
* Copyright (c) 2018-2020 CWI & Swat.engineering 
*
* This program and the accompanying materials are made available under the
* terms of the Eclipse Public License 2.0 which is available at
* http://www.eclipse.org/legal/epl-2.0.
*
* This Source Code may also be made available under the following Secondary
* Licenses when the conditions for such availability set forth in the Eclipse
* Public License, v. 2.0 are satisfied: GNU General Public License, version 2
* with the GNU Classpath Exception which is
* available at https://www.gnu.org/software/classpath/license.html.
*
* SPDX-License-Identifier: EPL-2.0 OR GPL-2.0 WITH Classpath-exception-2.0
********************************************************************************/

module lang::typhonql::relational::SQL


data SQLStat
  = create(str table, list[Column] cols, list[TableConstraint] constraints)
  | \insert(str table, list[str] colNames, list[SQLExpr] values)
  | update(str table, list[Set] sets, list[Clause] clauses)
  | delete(str table, list[Clause] clauses)
  | deleteJoining(list[str] joinTables, list[Clause] clauses)
  | select(list[SQLExpr] exprs, list[As] tables, list[Clause] clauses)
  | alterTable(str table, list[Alter] alters)
//  | renameTable(str table, str newName)
  | dropTable(list[str] tableNames, bool ifExists, list[DropOption] options)
  ;


data DropOption
  = restrict()
  | cascade();

data Set
  = \set(str column, SQLExpr expr);

  
data Alter
  = addConstraint(TableConstraint constraint)
  | dropConstraint(str constraintName)
  | dropIndex(str indexName)
  | addColumn(Column column)
  | dropColumn(str columnName)
  | renameColumn(str columnName, str newName)
  | renameTable(str newName)
  ;

  
data SQLExpr
  = column(str table, str name) // NB: always qualified
  | column(str name) // only for use in update
  | lit(Value val)
  | var(str name)
  | named(SQLExpr arg, str as) // select p.name as x1
  | placeholder(str name = "") // for representing ? or :name 
  | not(SQLExpr arg) 
  | neg(SQLExpr arg) 
  | pos(SQLExpr arg) 
  | mul(SQLExpr lhs, SQLExpr rhs) 
  | div(SQLExpr lhs, SQLExpr rhs) 
  | add(SQLExpr lhs, SQLExpr rhs) 
  | sub(SQLExpr lhs, SQLExpr rhs) 
  | equ(SQLExpr lhs, SQLExpr rhs) 
  | neq(SQLExpr lhs, SQLExpr rhs) 
  | leq(SQLExpr lhs, SQLExpr rhs) 
  | geq(SQLExpr lhs, SQLExpr rhs) 
  | lt(SQLExpr lhs, SQLExpr rhs) 
  | gt(SQLExpr lhs, SQLExpr rhs) 
  | like(SQLExpr lhs, SQLExpr rhs) 
  | or(SQLExpr lhs, SQLExpr rhs) 
  | and(SQLExpr lhs, SQLExpr rhs) 
  | notIn(SQLExpr arg, list[SQLExpr] vals)
  | \in(SQLExpr arg, list[SQLExpr] vals)
  | fun(str name, list[SQLExpr] args)
  | distance(SQLExpr lhs, SQLExpr rhs)
  ;


data As
  = as(str table, str name)
  | leftOuterJoin(As left, As right, SQLExpr on)
  | leftOuterJoin(As left, list[As] rights, list[SQLExpr] ons)
  ;

data Clause
  = where(list[SQLExpr] exprs)
  | groupBy(list[SQLExpr] exprs) // for now just column(t,n) is supported
  | having(list[SQLExpr] exprs)
  | orderBy(list[SQLExpr] exprs, Dir dir)
  | limit(SQLExpr expr)
  | offset(SQLExpr expr)
  ; 
  
data Dir
 = asc()
 | desc()
 ;

  
data Column
  = column(str name, ColumnType \type, list[ColumnConstraint] constraints);

data ColumnConstraint
  = notNull()
  | unique()
  ;

data TableConstraint
  = primaryKey(str column)
  | foreignKey(str column, str parent, str key, OnDelete onDelete)
  | index(str indexName, IndexKind kind, list[str] columns)
  ;
  
data IndexKind
    = uniqueIndex()
    | fullText()
    | spatial()
    | regular()
    ;
  
data OnDelete
  = cascade()
  | nothing()
  ;

// https://dev.mysql.com/doc/refman/8.0/en/data-types.html  
data ColumnType
  = varchar(int size)
  | char(int size)
  | text()
  | integer()
  | bigint()
  | float()
  | double()
  | blob()
  | point()
  | polygon()
  | date()
  | uuidType()
  | dateTime()
  | boolean()
  ; 
  
data Value
  = text(str strVal)
  | decimal(real realVal)
  | integer(int intVal)
  | boolean(bool boolVal)
  | point(real x, real y)
  | polygon(list[lrel[real, real]] segs)
  | dateTime(datetime dateTimeVal)
  | date(datetime dateVal)
  | placeholder(str name="")
  | blobPointer(str id)
  | sUuid(str uuid)
  | null()
  ;
