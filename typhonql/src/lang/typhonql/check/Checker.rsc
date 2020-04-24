module lang::typhonql::check::Checker

import ParseTree;
import String;
import lang::typhonml::TyphonML;
import lang::typhonml::Util;
extend analysis::typepal::TypePal;

extend lang::typhonql::TDBC;

/***********
 *  Types  *
 ***********/

data AType
    = voidType()
    | intType()
    | bigIntType()
    | uuidType()
    | stringType()
    | textType()
    | pointType()
    | polygonType()
    | boolType()
    | floatType()
    | blobType()
    | freeTextType(list[str] nlpFeatures)
    | dateType()
    | dateTimeType()
    ;

str prettyAType(voidType()) = "void";
str prettyAType(intType()) = "int";
str prettyAType(bigIntType()) = "bigint";
str prettyAType(uuidType()) = "uuid";
str prettyAType(stringType()) = "string";
str prettyAType(textType()) = "text";
str prettyAType(pointType()) = "point";
str prettyAType(polygonType()) = "polygon";
str prettyAType(boolType()) = "bool";
str prettyAType(floatType()) = "float";
str prettyAType(blobType()) = "blob";
str prettyAType(freeTextType(nlps)) = "freetext[<intercalate(",", [n | n <- nlps])>]";
str prettyAType(dateType()) = "date";
str prettyAType(dateTimeType()) = "datetime";
    
    
data AType
    = entityType(str name)
    | userDefinedType(str name)
    ;

str prettyAType(entityType(str name)) = name;
str prettyAType(userDefinedType(str name)) = name;

bool qlSubType(intType(), bigIntType()) = true;
bool qlSubType(intType(), floatType()) = true;
bool qlSubType(bigIntType(), floatType()) = true;

bool qlSubType(stringType(), textType()) = true;
bool qlSubType(textType(), stringType()) = true;

bool qlSubType(uuidType(), entityType(_)) = true;

bool qlSubType(voidType(), _) = true;

default bool qlSubType(AType a, AType b) = false;

alias CheckerMLSchema = map[AType entity, map[str field, tuple[AType typ, Cardinality card] tp] fields];
data TypePalConfig(CheckerMLSchema mlSchema = ());

/***********
 *  Roles  *
 ***********/
 
 data IdRole
    = tableRole()
    | fieldRole()
    ;
 

/****************/
/** Expression **/
/****************/

void collect(current:(Expr)`<VId var> . <{Id "."}+ attrs>`, Collector c) {
    c.use(var, {tableRole()});
    Tree parent = var;
    for (a <- attrs) {
        c.useViaType(parent, a, {fieldRole()});
        parent = a;
    }
    c.fact(current, parent);
}

void collect(current:(Expr)`<VId var>`, Collector c) {
    collect(var, c);
}

void collect(VId current, Collector c) {
    c.use(current, {tableRole()});
}

void collect(current:(Expr)`<PlaceHolder p>`, Collector c) {
    c.fact(p, voidType());
}

void collect(current:(Expr)`<VId var>. @id`, Collector c) {
    c.fact(current, uuidType());
    c.use(var, {tableRole()});
}

void collect((Expr)`<Int i>`, Collector c) {
    c.fact(i, intType());
}

void collect((Expr)`<Str s>`, Collector c) {
    c.fact(s, stringType());
}

void collect((Expr)`<Real r>`, Collector c) {
    c.fact(r, floatType());
}

void collect((Expr)`<DateTime dt>`, Collector c) {
    c.fact(dt, dateTimeType());
}

void collect((Expr)`<Point pt >`, Collector c) {
    c.fact(pt, pointType());
}

void collect((Expr)`<Polygon pg>`, Collector c) {
    c.fact(pg, polygonType());
}


void collect((Expr)`<Bool b>`, Collector c) {
    c.fact(b, boolType());
}

void collect((Expr)`<UUID u>`, Collector c) {
    c.fact(u, uuidType());
}

void collect(current:(Expr)`(<Expr arg>)`, Collector c) {
    c.fact(current, arg);
    collect(arg, c);
}

void collect(current:(Expr)`<Obj objValue>`, Collector c) {
    collect(objValue, c);
}

void collect(current:(Obj)`<Label? label> <EId entity> { <{KeyVal ","}* keyVals> }`, Collector c) {
    collectEntityType(entity, c);
    collectKeyVal(keyVals, entity, c);
}

void collectKeyVal({KeyVal ","}* keyVals, EId entity, Collector c) {
    for (kv <- keyVals) {
        collectKeyVal(kv, entity, c);
    }
}


void collectKeyVal(current:(KeyVal)`@id : <Expr val>`, EId entity, Collector c) {
    collect(val, c);
    c.requireEqual(uuidType(), val, error(current, "Expected uuid but got %t", val));
}

void collectKeyVal(current:(KeyVal)`<Id key> : <Expr val>`, EId entity, Collector c) {
    collect(val, c);
    c.useViaType(entity, key, {fieldRole()});
    c.require("valid assignment", current, [key, val], void (Solver s) {
        if (atypeList([uuidType()]) := s.getType(val)) {
            requireValidCardinality(current, key, entity, s);
        }
        else {
            s.requireTrue(s.equal(key, val) || s.subtype(val, key), error(current, "Expected %t but got %t", key, val));
        }
    });
}

void collectKeyVal(current:(KeyVal)`<Id key> +: <Expr val>`, EId entity, Collector c) {
    collectKVUpdate(current, key, val, entity, c);
}

void collectKeyVal(current:(KeyVal)`<Id key> -: <Expr val>`, EId entity, Collector c) {
    collectKVUpdate(current, key, val, entity, c);
}

void collectKVUpdate(KeyVal current, Id key, Expr val, EId entity, Collector c) {
    collect(val, c);
    c.useViaType(entity, key, {fieldRole()});
    c.requireEqual(atypeList([uuidType()]), val, error(val, "Currently only lists of uuids are supported in the update syntax"));
    c.require("valid update", current, [key, val], void (Solver s) {
        requireValidCardinality(current, key, entity, s);
    });
}

void requireValidCardinality(KeyVal current, Id key, EId entity, Solver s) {
    keyType = s.getType(key);
    s.requireTrue(entityType(_) := keyType, error(key, "Expected entity type, got %t", key));
    cardinality = getCardinality(entity, key, s);
    s.requireTrue(cardinality in {zero_many(), one_many()}, error(current, "update not supported on cardinality one or zero-to-one"));
}


void collect(current:(Expr)`<Custom customValue>`, Collector c) {
    reportUnsupported(current, c);
}

//void collect(current:(Expr)`[<{Obj ","}*entries>]`, Collector c) {
//    if (e <- entries) {
//        collect(entries, c);
//        c.calculate("list type", current, [et | et <- entries], AType (Solver s) {
//            for (et <- entries) {
//                s.requireEqual(e, et, error(et, "Expected same type in the list, found %t and %t", e, et));
//            }
//            return atypeList([s.getType(e)]);
//        });
//    }
//    c.fact(current, atypeList([voidType()]));
//}

void collect(current:(Expr)`[<{UUID ","}* refs>]`, Collector c) {
    c.fact(current, atypeList([uuidType()]));
}

void collect(current:(Expr)`null`, Collector c) {
    c.fact(current, voidType());
}

void collect(current:(Expr)`+ <Expr arg>`, Collector c) {
    collect(arg, c);
    c.fact(current, arg);
    c.requireComparable(intType(), arg, error(arg, "Numeric type expected, got %t", arg));
}

void collect(current:(Expr)`- <Expr arg>`, Collector c) {
    collect(arg, c);
    c.fact(current, arg);
    c.requireComparable(intType(), arg, error(arg, "Numeric type expected, got %t", arg));
}

void collect(current:(Expr)`<VId name> (<{Expr ","}* args>)`, Collector c) {
    reportUnsupported(current, c);
}

void collect(current:(Expr)`! <Expr arg>`, Collector c) {
    collect(arg, c);
    c.fact(current, boolType());
    c.requireEqual(boolType(), arg, error(arg, "Expected bool type, got %t", arg));
}



void collect(current:(Expr)`<Expr lhs> * <Expr rhs>`, Collector c) {
    collectInfix(lhs, rhs, "*", current, c);
}

void collect(current:(Expr)`<Expr lhs> / <Expr rhs>`, Collector c) {
    collectInfix(lhs, rhs, "/", current, c);
}

void collect(current:(Expr)`<Expr lhs> + <Expr rhs>`, Collector c) {
    collectInfix(lhs, rhs, "+", current, c);
}

void collect(current:(Expr)`<Expr lhs> - <Expr rhs>`, Collector c) {
    collectInfix(lhs, rhs, "-", current, c);
}

void collect(current:(Expr)`<Expr lhs> == <Expr rhs>`, Collector c) {
    collectBoolInfix(lhs, rhs, "==", current, c);
}

void collect(current:(Expr)`<Expr lhs> != <Expr rhs>`, Collector c) {
    collectBoolInfix(lhs, rhs, "!=", current, c);
}

void collect(current:(Expr)`<Expr lhs> \>= <Expr rhs>`, Collector c) {
    collectBoolInfix(lhs, rhs, "\>=", current, c);
}

void collect(current:(Expr)`<Expr lhs> \<= <Expr rhs>`, Collector c) {
    collectBoolInfix(lhs, rhs, "\<=", current, c);
}

void collect(current:(Expr)`<Expr lhs> \> <Expr rhs>`, Collector c) {
    collectBoolInfix(lhs, rhs, "\>", current, c);
}

void collect(current:(Expr)`<Expr lhs> \< <Expr rhs>`, Collector c) {
    collectBoolInfix(lhs, rhs, "\<", current, c);
}

void collect(current:(Expr)`<Expr lhs> in <Expr rhs>`, Collector c) {
    reportUnsupported(current, c);
}

void collect(current:(Expr)`<Expr lhs> like <Expr rhs>`, Collector c) {
    reportUnsupported(current, c);
}

void collect(current:(Expr)`<Expr lhs> && <Expr rhs>`, Collector c) {
    collectBoolInfix(lhs, rhs, "&&", current, c);
}

void collect(current:(Expr)`<Expr lhs> || <Expr rhs>`, Collector c) {
    collectBoolInfix(lhs, rhs, "||", current, c);
}

// TODO: in + like

void collectInfix(Expr lhs, Expr rhs, str op, Expr current, Collector c) {
    collect(lhs, rhs, c);
    c.calculate("<op>", current, [lhs, rhs], AType (Solver s) {
        try {
            return calcInfix(op, {s.getType(lhs), s.getType(rhs)}, s);
        } catch "unsupported": {
            s.report(error(current, "%v not supported between %t and %t", op, lhs, rhs));
            return intType(); // never reached since error throws an exception
        }
    });
}

void collectBoolInfix(Expr lhs, Expr rhs, str op, Expr current, Collector c) {
    collect(lhs, rhs, c);
    c.fact(current, boolType());
    if (op in {"&&", "||"}) {
        c.requireEqual(boolType(), lhs, error(lhs, "%v expects bool types (got %t)", lhs));
        c.requireEqual(boolType(), rhs, error(rhs, "%v expects bool types (got %t)", rhs));
    }
    else {
        c.requireComparable(lhs, rhs, error(current, "Cannot compare %t and %t", lhs, rhs));
        if (op notin {"==", "!="}) {
            // we only have to check one side to know if they are incorrect
            c.require(op, current, [lhs], void (Solver s) {
                s.requireTrue(s.getType(lhs) in orderableTypes, error(current, "Cannot compare things of type %t", lhs));
            });
        }
    }
}


set[str] mathOps = {"+", "*", "/", "-"};
set[AType] numericTypes = {intType(), stringType(), floatType()};
set[AType] orderableTypes = numericTypes + {dateTimeType(), dateType()};

AType calcInfix(str op, {AType singleType}, _) = singleType
    when op in mathOps && singleType in numericTypes;

AType calcInfix(str op, {intType(), floatType()}, _) = floatType()
    when op in mathOps;
   
AType calcInfix("+", {stringType(), _}, _) = stringType(); // allow concat on many things
    
default AType calcInfix(_, _, _) {
    throw "unsupported";
}

void collectEntityType(EId entityName, Collector c) {
    tp = entityType("<entityName>");
    if (tp in c.getConfig().mlSchema) {
        c.fact(entityName, tp);
    }
    else {
        c.calculate("error", entityName, [], AType (Solver s) {
            s.report(error(entityName, "Missing model in the typepal configuration"));
            return voidType();
        });
    }
}


/***********/
/** Query **/
/***********/

void collect(current:(Query)`from <{Binding ","}+ bindings> select <{Result ","}+ selected> <Where? where> <GroupBy? groupBy> <OrderBy? orderBy>`, Collector c) {
    c.enterScope(current);
    collect(bindings, selected, c);
    if (w <- where) {
        collect(w, c);
    }
    if (g <- groupBy) {
        collect(g, c);
    }
    if (ob <- orderBy) {
        collect(ob, c);
    }
    c.leaveScope(current);
}

void collect(Result current, Collector c) {
    collect(current.expr, c);
}

void collect(current:(Binding)`<EId entity> <VId name>`, Collector c) {
    collectEntityType(entity, c);
    c.define("<name>", tableRole(), name, defType(entity));
}


void collect((Where)`where <{Expr ","}+ clauses>`, Collector c) {
    collect(clauses, c);
    for (cl <- clauses) {
        c.requireEqual(boolType(), cl, error(cl, "Where expects a boolean expression"));
    }
}

void collect((GroupBy)`group <{Expr ","}+ vars> <Having? having>`, Collector c) {
    collect(vars, c);
    if (h <- having) {
        collect(h, c);
    }
}

void collect((Having)`having <{Expr ","}+ clauses>`, Collector c) {
    collect(clauses, c);
    for (cl <- clauses) {
        c.requireEqual(boolType(), cl, error(cl, "Having expects a boolean expression"));
    }
}

void collect((OrderBy)`order <{Expr ","}+ vars>`, Collector c) {
    collect(vars, c);
}

/*******
 * DML *
 *******/
 
void collect(current:(Statement)`insert <{Obj ","}* objs>`, Collector c) {
    c.enterScope(current);
    collect(objs, c);
    // todo check that +: and -: aren't used in insert query
    c.leaveScope(current);
}


void collect(current:(Statement)`delete <Binding b> <Where? where>`, Collector c) {
    c.enterScope(current);
    collect(b, c);
    if (w <- where) {
        collect(w, c);
    }
    c.leaveScope(current);
}

void collect(current:(Statement)`update <Binding b> <Where? where> set { <{KeyVal ","}* keyVals>}`, Collector c) {
    c.enterScope(current);
    collect(b, c);
    if (w <- where) {
        collect(w, c);
    }
    collectKeyVal(keyVals, b.entity, c);
    c.leaveScope(current);
}


/**********
 * Script *
 **********/
 
void collect(current:(Script)`<Scratch scratch>`, Collector c) {
    collect(scratch, c);
 }

void collect(current:(Scratch)`<Request* requests>`, Collector c) {
    collect(requests, c);
}

void collect(current:(Request)`<Query qry>`, Collector c) {
    collect(qry, c);
}

void collect(current:(Request)`<Statement stm>`, Collector c) {
    collect(stm, c);
}

/*******
 * DDL *
 *******/
 
void collect(current: (Statement)`create <EId _> at <Id _>`, Collector c) {
    reportUnsupported(current, c);
}
void collect(current: (Statement)`create <EId _> . <Id _> : <Type _>`, Collector c) {
    reportUnsupported(current, c);
} 
void collect(current: (Statement)`create <EId _> . <Id _> <Inverse? _> <Arrow _> <EId _> [ <CardinalityEnd _> .. <CardinalityEnd _> ]`, Collector c) {
    reportUnsupported(current, c);
}
void collect(current: (Statement)`drop <EId _>`, Collector c) {
    reportUnsupported(current, c);
}
void collect(current: (Statement)`drop attribute <EId _> . <Id _>`, Collector c) {
    reportUnsupported(current, c);
}
void collect(current: (Statement)`drop relation <EId _> . <Id _>`, Collector c) {
    reportUnsupported(current, c);
}
void collect(current: (Statement)`rename attribute <EId _> . <Id _> to <Id _>`, Collector c) {  
    reportUnsupported(current, c);
}
void collect(current: (Statement)`rename relation <EId _> . <Id _> to <Id _>`, Collector c) {  
    reportUnsupported(current, c);
}

void reportUnsupported(Tree current, Collector c) {
    c.calculate("unsupported", current, [], AType (Solver s) {
        s.report(error(current, "`%v` is not supported the typechecker (yet)", current));
        return voidType();
    });
}

Cardinality getCardinality(EId context, Id fname, Solver s) {
    mlSchema = s.getConfig().mlSchema;
    utype = s.getType(context);
    if (utype in mlSchema) {
        if ("<fname>" in mlSchema[utype]) {
            return mlSchema[utype]["<fname>"].card;
        }
    }
    s.report(error(fname, "<fname> not defined for %t", utype));
    return \one();
}


private TypePalConfig buildConfig(bool debug, CheckerMLSchema mlSchema) 
    = tconfig(
        verbose=debug, logTModel = debug,
        isSubType = qlSubType,
        mlSchema = mlSchema,
        getTypeNamesAndRole = tuple[list[str] typeNames, set[IdRole] idRoles] (AType tp) {
            return <[], {}>;
        },
        getTypeInNamelessType = 
            AType(AType utype, Tree fname, loc scope, Solver s) {
                if (utype in mlSchema) {
                    if ("<fname>" in mlSchema[utype]) {
                        return mlSchema[utype]["<fname>"].typ;
                    }
                }
                s.report(error(fname, "<fname> not defined for %t", utype));
                return voidType();
            }
    );

AType calcMLType("int") = intType();
AType calcMLType("bigint") = intType();
AType calcMLType(/^string[\[\(]/) = stringType();
AType calcMLType("text") = stringType();
AType calcMLType("point") = pointType();
AType calcMLType("polygon") = polygonType();
AType calcMLType("bool") = boolType();
AType calcMLType("float") = floatType();
AType calcMLType("blob") = blobType();
AType calcMLType(/^freetext\[<features:.*>\]$/) = freeTextType([trim(f) | f <- split(",", features)]);
AType calcMLType("date") = dateType();
AType calcMLType("datetime") = dateTimeType();

default AType calcMLType(str tp) {
    throw "Forgot to add support for type <tp>";
}



CheckerMLSchema convertModel(Schema mlSchema) 
    = ( 
        entityType(tpn) : 
        (( fn : <calcMLType(ftp), \one()> | <fn, ftp> <- mlSchema.attrs[tpn])
        + (fr : <entityType(to), fc> | <fc, fr, _, _, to, _> <- mlSchema.rels[tpn])
        + (tr : <entityType(from), tc> | <from, _, _, tr, tc, tpn, _> <- mlSchema.rels)) // inverse roles
    | tpn <- entities(mlSchema)
    );


TModel checkQLTree(Tree t, CheckerMLSchema mlSchema, bool debug = false) {
    if (t has top) {
        t = t.top;
    }
    return collectAndSolve(t, config=buildConfig(debug, mlSchema));
}

TModel checkQLTree(Tree t, Schema mlSchema, bool debug = false) 
    = checkQLTree(t, convertModel(mlSchema), debug = debug);

