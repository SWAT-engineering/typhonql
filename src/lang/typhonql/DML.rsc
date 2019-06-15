module lang::typhonql::DML

extend lang::typhonql::Expr;
extend lang::typhonql::Query;


syntax Statement
  = "insert" {Obj ","}* objs
  | "delete" Binding binding Where? where
  | "update" Binding Where? where "set"  "{" {KeyVal ","}* keyVals "}" 
  ;
  

