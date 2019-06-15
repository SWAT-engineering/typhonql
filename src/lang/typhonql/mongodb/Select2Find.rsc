module lang::typhonql::mongodb::Select2Find

import lang::typhonql::mongodb::DBCollection;
import lang::typhonql::Query;
import lang::typhonml::Util;
import String;

/*

Approach:

containments become nested DBObjs (patterns)

wheres on entities should anded and put on the dbobj queries.

How to determine whether an entity becomes a collection
or anonymously nested?

I guess if it's contained, and there are no incoming xrefs to it the entity, otherwise, we need a reference identifier


entities to be retrieved:
- all entities x that have a path ending at it in the results
- all entities x that have a paths to an attr in x in the results

collections to be queried
- all collections of the from clause?



*/

map[str, CollMethod] select2find((Query)`from <{Binding ","}+ bs> select <{Result ","}+ rs>`, Schema s)
  = select2find((Query)`from <{Binding ","}+ bs> select <{Result ","}+ rs> where true`, s);


map[str, CollMethod] select2find((Query)`from <{Binding ","}+ bs> select <{Result ","}+ rs> where <{Expr ","}* es>`, Schema s) {
  Env env = ( "<b.var>": "<b.entity>" | Binding b <- bs );
  map[str, CollMethod] result = ( "<b.entity>": find(object([]), object([])) | Binding b <- bs );
  
  
  for ((Result)`<VId x>.<{Id "."}+ fs>` <- rs) {
    result[env["<x>"]].projection.props += [<"_typhon_id", \value(1)>, <"<fs>", \value(1)>];
  }
 
  for (Expr e <- es) {
    <coll, p> = expr2pattern(e, env);
    result[coll].query.props += [p];
  }
  
  return result;
}

alias Env = map[str, str];

tuple[str, Prop] expr2pattern((Expr)`<Expr lhs> == <Expr rhs>`, Env env)
  = <coll, <path, expr2obj(other)>> 
  when
    <str coll, str path, Expr other> := split(lhs, rhs, env);
    
tuple[str, Prop] expr2pattern((Expr)`<Expr lhs> != <Expr rhs>`, Env env)
  = makeComparison("$ne", lhs, rhs, env);
  

tuple[str, Prop] expr2pattern((Expr)`<Expr lhs> \> <Expr rhs>`, Env env)
  = makeComparison("$gt", lhs, rhs, env);

tuple[str, Prop] expr2pattern((Expr)`<Expr lhs> \< <Expr rhs>`, Env env)
  = makeComparison("$lt", lhs, rhs, env);

tuple[str, Prop] expr2pattern((Expr)`<Expr lhs> \>= <Expr rhs>`, Env env)
  = makeComparison("$gte", lhs, rhs, env);

tuple[str, Prop] expr2pattern((Expr)`<Expr lhs> \<= <Expr rhs>`, Env env)
  = makeComparison("$lte", lhs, rhs, env);
  

default tuple[str, Prop] expr2pattern(Expr e, Env env) { 
  throw "Unsupported expression: <e>"; 
}

  
tuple[str, Prop] makeComparison(str op, Expr lhs, Expr rhs, Env env) 
  = <coll, <path, object([<op, expr2obj(other)>])>> 
  when
    <str coll, str path, Expr other> := split(lhs, rhs, env);
    
    
// NB: restriction is that the same collection cannot be queried with different vars
// also paths in vars now must end at  primitives.
 
tuple[str coll, str path, Expr other] split(Expr lhs, Expr rhs, Env env) {
  if ((Expr)`<VId x>.<{Id "."}+ fs>` := lhs) {
    return <env["<x>"], "<fs>", rhs>; 
  }
  else if ((Expr)`<VId x>.<{Id "."}+ fs>` := rhs) {
    return <env["<x>"], "<fs>", lhs>;
  }
  else {
    throw "One of binary expr must be contained field navigation, but got: <lhs>, <rhs>";
  }
}
    

DBObject expr2obj((Expr)`<Int i>`) = \value(toInt("<i>"));

// todo: unescaping
DBObject expr2obj((Expr)`<Str s>`) = \value("<s>"[1..-1]);

DBObject expr2obj((Expr)`<Bool b>`) = \value("<b>" == true);

default DBObject expr2obj(Expr e) { throw "Unsupported MongoDB restriction expression: <e>"; }
