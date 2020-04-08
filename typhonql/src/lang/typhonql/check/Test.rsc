module lang::typhonql::check::Test

import lang::typhonml::TyphonML;
import lang::typhonql::check::Checker;
extend analysis::typepal::TestFramework;

TModel checkQLTree(Tree e, CheckerMLSchema schema, bool debug) = checkQLTree(e, schema, debug = debug);

test bool runExprTest(bool debug = false)
    = runTests([|project://typhonql/src/lang/typhonql/check/expressions.ttl|], 
            #Expr, 
            TModel (t) { return checkQLTree(t, (), debug); }, 
            runName = "QL Expressions");
            
            
CheckerMLSchema queriesModel = (
    entityType("User"): (
        "name": stringType()
    )
);
            
test bool runQueryTest(bool debug = false) 
    = runTests([|project://typhonql/src/lang/typhonql/check/queries.ttl|], 
            #Query, 
            TModel (t) { return checkQLTree(t, queriesModel, debug); }, 
            runName = "QL Queries");

test bool runDMLTest(bool debug = false) 
    = runTests([|project://typhonql/src/lang/typhonql/check/dml.ttl|], 
            #Statement, 
            TModel (t) { return checkQLTree(t, queriesModel, debug); }, 
            runName = "QL DML");