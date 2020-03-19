module lang::typhonml::XMIReader

import lang::xml::IO;
import lang::typhonml::TyphonML;
import lang::ecore::Refs;

import lang::typhonml::Util;

import IO;
import Node;
import Type;

import util::ValueUI;

void smokeTest() {
  str xmi = readFile(|project://typhonql/src/test/changeTypeAttributeChangeOperator.xmi|);
  Model m = xmiString2Model(xmi);
  iprintln(m);
  iprintln(model2schema(m));
}


void smokeTest2() {
  str xmi = readFile(|project://typhonql/src/lang/typhonml/customdatatypes.xmi|);
  Model m = xmiString2Model(xmi);
  Schema s = model2schema(m);
  //iprintln(m);
  iprintln(s);
}

Model loadTyphonML(loc l) = xmiString2Model(readFile(l));

Model xmiString2Model(str s) = xmiNode2Model(readXML(s, fullyQualify=true));

Schema loadSchemaFromXMI(str s) = model2schema(m)
	when Model m := xmiString2Model(s);

@doc{
Convert a node representation of the XMI serialization of a TyphonML model
to a `lang::typhoml::TyphonML::Model` value.

Omissions for now:
 - evolution operators
 - database types other than document and relation
}
Model xmiNode2Model(node n) {  
  Realm realm = newRealm();
  
  list[Database] dbs = [];
  list[DataType] dts = [];
  list[ChangeOperator] chos = [];
  
  str get(node n, str name) = x 
    when str x := getKeywordParameters(n)[name];
    
  bool has(node n, str name) = name in (getKeywordParameters(n));
  
  map[str, DataType] typeMap = ();
  map[str, Relation] relMap = ();
  map[str, Database] dbMap = ();
  map[str, Attribute] attrMap = ();
  
  DataType ensureEntity(str path) {
    if (path notin typeMap) {
      typeMap[path] = DataType(realm.new(#Entity, Entity("", [], [], [])));
    }
    return typeMap[path];
  }
  /*
  Database ensureDatabase(str path) {
    if (path notin dbMap) {
      dbMap[path] = NamedElement(realm.new(#Database, Database("")));
    }
    return dbMap[path];
  }
  */
  
  DataType ensurePrimitive(str path) {
    if (path notin typeMap) {
      typeMap[path] = DataType(realm.new(#PrimitiveDataType, PrimitiveDataType("")));
    }
    else {
      typeMap[path] = DataType(realm.new(#PrimitiveDataType, PrimitiveDataType(""), id = typeMap[path].uid));
    }
    return typeMap[path];
  }
  
  DataType ensureCustom(str path) {
    if (path notin typeMap) {
      typeMap[path] = DataType(realm.new(#CustomDataType, CustomDataType("", [])));
    }
    else {
      typeMap[path] = DataType(realm.new(#CustomDataType, CustomDataType("", []), id = typeMap[path].uid));
    }
    
    return typeMap[path];
  }
  
  
  Relation ensureRel(str path) {
    if (path notin relMap) {
      relMap[path] = realm.new(#Relation, Relation("", zero_one()));
    }
    return relMap[path];
  }
  
  Attribute ensureAttr(str path) {
    if (path notin attrMap) {
      attrMap[path] = realm.new(#Attribute, Attribute(""));
    }
    return attrMap[path];
  }
  
  if ("typhonml:Model"(list[node] kids) := n) {

	int dbPos = 0;
	
    for (xdb:"databases"(list[node] xelts) <- kids) {
      dbPath = "//@dataTypes.<dbPos>";
    	
      switch (get(xdb, "xsi:type")) {
        case "typhonml:RelationalDB": {
          tbls = [];
          for (xtbl:"tables"(_) <- xelts) {
            tbl = realm.new(#Table, Table(get(xtbl, "name")));
            ep = get(xtbl, "entity");
            tbl.entity = referTo(#Entity, ensureEntity(ep).entity);
            tbls += [tbl];
          }
          
          dbs += [ realm.new(#Database, Database(RelationalDB(get(xdb, "name"), tbls)))];
        }
        
        case "typhonml:DocumentDB": {
          colls = [];
          for (xcoll:"collections"(_) <- xelts) {
            coll = realm.new(#Collection, Collection(get(xcoll, "name")));
            ep = get(xcoll, "entity");
            coll.entity = referTo(#Entity, ensureEntity(ep).entity);
            colls += [coll];
          }
          
          dbs += [ realm.new(#Database, Database(DocumentDB(get(xdb, "name"), colls))) ];
        }
        
        default:
          throw "Non implemented database type: <xdb.\type>";
      }
      dbPos += 1;
    }
    
    
    int dtPos = 0;
    for (xdt:"dataTypes"(list[node] xelts) <- kids) {
       dtPath = "//@dataTypes.<dtPos>";
           
       switch (get(xdt, "xsi:type")) {
       	 case "typhonml:PrimitiveDataType": {
           pr = ensurePrimitive(dtPath).primitiveDataType;
           pr.name = get(xdt, "name");
           dts += [DataType(pr)];
         }
         
         case "typhonml:CustomDataType": {
           list[DataTypeItem] elements = [];
           for (xattr:"elements"(_) <- xelts) {
             el = realm.new(#DataTypeItem, DataTypeItem(get(xattr, "name"), DataTypeImplementationPackage()));
             aPath = get(xattr, "type");
             el.\type = referTo(#DataType, ensurePrimitive(aPath));
             elements += [el]; 
           }
           custom = ensureCustom(dtPath).customDataType;
           custom.name = get(xdt, "name");
           custom.elements = elements;   
           dt = DataType(custom);  
           dts+= [dt];
         }
         
         case "typhonml:Entity": {
           attrs = [];
           attrPos = 0;
           for (xattr:"attributes"(_) <- xelts) {
           	 attrPath = "<dtPath>/@attributes.<attrPos>";
           	 attr = ensureAttr(attrPath);
             attr.name = get(xattr, "name");
             aPath = get(xattr, "type");
             attr.\type = referTo(#DataType, ensurePrimitive(aPath));
             attrs += [attr]; 
           }  
         
           rels = [];
           relPos = 0;
           for (xrel:"relations"(_) <- xelts) {
             relPath = "<dtPath>/@relations.<relPos>";
             myrel = ensureRel(relPath);
             myrel.name = get(xrel, "name");
             if (has(xrel, "cardinality"))
             	myrel.cardinality = make(#Cardinality, get(xrel, "cardinality"), []);
             else
             	myrel.cardinality =  make(#Cardinality, "zero_one", []);
             
             ePath = get(xrel, "type");
             myrel.\type = referTo(#Entity, ensureEntity(ePath).entity);
             
             if ("opposite" in getKeywordParameters(xrel)) {
               oppPath = get(xrel, "opposite");
               myrel.opposite = referTo(#Relation, ensureRel(oppPath));
             }
             
             if ("isContainment" in getKeywordParameters(xrel)) {
               myrel.isContainment = get(xrel, "isContainment") == "true";
             } 
           
             rels += [myrel];
             relPos += 1;
           }

           entity = ensureEntity(dtPath).entity;
           entity.name = get(xdt, "name");
           entity.attributes = attrs;
           entity.fretextAttributes = []; // todo;
           entity.relations = rels;
           dt = DataType(entity);              
           dts += [dt];
         }
       }
       
       dtPos += 1;
    }
    
    int chOpPos = 0;
    for (xcho:"changeOperators"(list[node] xelts) <- kids) {
      dtPath = "//@changeOperators.<chOpPos>";
      
      switch (get(xcho, "xsi:type")) {
      	
      	case "typhonml:AddEntity":{
      		
      		attrs = [];
           	for (xattr:"attributes"(_) <- xcho) {
             	attr = realm.new(#Attribute, Attribute(get(xattr, "name")));
             	aPath = get(xattr, "type");
             	attr.\type = referTo(#DataType, ensurePrimitive(aPath));
             	attrs += [attr]; 
           	}  
           	
           	
           	rels = [];
           	relPos = 0;
          	for (xrel:"relations"(_) <- xcho) {
             	relPath = "<dtPath>/@relations.<relPos>";
             	myrel = ensureRel(relPath);
             	myrel.name = get(xrel, "name");
             	if (has(xrel, "cardinality"))
             		myrel.cardinality = make(#Cardinality, get(xrel, "cardinality"), []);
             	else
             		myrel.cardinality =  make(#Cardinality, "zero_one", []);
             
             	ePath = get(xrel, "type");
             	myrel.\type = referTo(#Entity, ensureEntity(ePath).entity);
             
             	if ("opposite" in getKeywordParameters(xrel)) {
               		oppPath = get(xrel, "opposite");
               		myrel.opposite = referTo(#Relation, ensureRel(oppPath));
             	}
             
             	if ("isContainment" in getKeywordParameters(xrel)) {
               		myrel.isContainment = get(xrel, "isContainment") == "true";
             	} 
           
             	rels += [myrel];
             	relPos += 1;
           	}
           	
           	name = get(xcho, "name");
      		re = realm.new(#AddEntity, AddEntity(name, attrs, [], rels));
      		chos += [ ChangeOperator(re)];
           	
           	entity = ensureEntity(dtPath).entity;
           	entity.name = name;
           	entity.attributes = attrs;
           	entity.fretextAttributes = []; // todo;
           	entity.relations = rels;
           	dt = DataType(entity);   
           	
      		dts += [dt];
      	}
      	
      	case "typhonml:AddRelation":{
      	
      		e = get(xcho, "ownerEntity");
      		entity = referTo(#Entity, ensureEntity(e).entity);
      		
      		cardinality = make(#Cardinality, "zero_one", []);
      		if (has(xcho, "cardinality"))
             	cardinality = make(#Cardinality, get(xcho, "cardinality"), []);

      		
      		containement = get(xcho, "isContainment") == "true";
      		name = get(xcho, "name");
      		
      		t = get(xcho, "type");
      		ty = referTo(#DataType, ensurePrimitive(t));
      		
      		re = realm.new(#AddRelation, AddRelation(\name = name, 
      												\cardinality = cardinality, 
      												\ownerEntity = entity, 
      												\isContainment = containement,
      												\type = ty));
      		println(re);
      		chos += [ ChangeOperator(re)];
      	}
      	
      	case "typhonml:AddAttribute":{
      		t = get(xcho, "type");
      		ty = referTo(#DataType, ensurePrimitive(t));
      		
      		e = get(xcho, "ownerEntity");
      		entity = referTo(#Entity, ensureEntity(e).entity);
      		
      		name = get(xcho, "name");
      		
      		re = realm.new(#AddAttribute, AddAttribute(\name = name, 
      													\ownerEntity = entity,
      													\type = ty));
      		chos += [ ChangeOperator(re)];
      	}
      	
      	case "typhonml:ChangeRelationCardinality":{
      		relPath = get(xcho, "relation");
      		
      		relref = referTo(#Relation ,ensureRel(relPath));
      		cardinality = make(#Cardinality, get(xcho, "newCardinality"), []);
      		
      		re = realm.new(#ChangeRelationCardinality, ChangeRelationCardinality(relref, cardinality));
      		chos += [ChangeOperator(re)];
      	}
      	
      	case "typhonml:ChangeRelationContainement": {
      		relPath = get(xcho, "relation");
      		
      		relref = referTo(#Relation ,ensureRel(relPath));
      		containement = get(xcho, "newContainment") == "true";
      		
      		re = realm.new(#ChangeRelationContainement, ChangeRelationContainement(relref, containement));
      		chos += [ChangeOperator(re)];
      	}
      	
      	case "typhonml:ChangeAttributeType": {
      		attr_path = get(xcho, "attributeToChange");
      		type_path = get(xcho, "newType");
      		
      		ty = referTo(#DataType, ensurePrimitive(type_path));
      		attr = referTo(#DataType, ensureAttr(attr_path));
      		
      		re = realm.new(#ChangeAttributeType, ChangeAttributeType(attr, ty));
      		chos += [ChangeOperator(re)];
      	}
      	
        case "typhonml:RemoveEntity": {
        	e = get(xcho, "entityToRemove");
        	toRemove = referTo(#Entity, ensureEntity(e).entity);
        	re = realm.new(#RemoveEntity, RemoveEntity(toRemove));
          	chos += [ ChangeOperator(re)];
        } // ChangeOperator(RemoveEntity \removeEntity, lang::ecore::Refs::Ref[Entity] \entityToRemove = \removeEntity.\entityToRemove, lang::ecore::Refs::Id uid = \removeEntity.uid, bool _inject = true) ];
        
         case "typhonml:RenameEntity": {
        	e = get(xcho, "entityToRename");
        	
        	newName = get(xcho, "newEntityName");
        	toRename = referTo(#Entity, ensureEntity(e).entity);
        	re = realm.new(#RenameEntity, RenameEntity(\entityToRename = toRename, \newEntityName = newName));
          	chos += [ ChangeOperator(re)];
        }
        default:
          throw "Non implemented change operator: <get(xcho, "type")>";
      }
      
      chOpPos += 1;
      
    }
    
    return  realm.new(#Model, Model(dbs, dts, chos));
  }
  else {
    throw "Invalid Typhon ML XMI node <n>";
  }
  
  
  
}