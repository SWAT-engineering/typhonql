module lang::typhonml::Syntax

import lang::std::Layout
import lang::std::Id;

start syntax Model
  = Model: DataType* dataTypes Database databases ("changeOperators" "[" ChangeOperator* changeOperators "]")?

DataType returns DataType:
	PrimitiveDataType_Impl | FreeText | CustomDataType | Entity_Impl;

ChangeOperator returns ChangeOperator:
	AddAttribute | AddEntity | AddRelation | RenameAttribute | RenameEntity |
	RenameRelation | RemoveAttribute | RemoveEntity | RemoveRelation | ChangeRelationCardinality
;

RenameAttribute returns RenameAttribute :
	'rename' 'attribute' attributeToRename=[Attribute|EString] 'as' newName=EString  
;

RenameEntity returns RenameEntity :
	'rename' 'Entity' entityToRename=[Entity|EString] 'as' newEntityName=EString  
;
RenameRelation returns RenameRelation:
	'rename' 'Relation' relationToRename=[Relation|EString] 'as' newRelationName=EString
;

RemoveAttribute returns RemoveAttribute :
	'remove' 'attribute' attributeToRemove=[Attribute|EString]  
;

RemoveEntity returns RemoveEntity :
	'remove' 'Entity' entityToRemove=[Entity|EString]  
;

RemoveRelation returns RemoveRelation:
	'remove' 'Relation' relationToRemove=[Relation|EString]
;

ChangeRelationContainement returns ChangeRelationContainement :
	'change' 'containment' relation=[Relation|EString] 'as' newContainment=EBooleanObject 
;

ChangeRelationCardinality returns ChangeRelationCardinality:
	'change' 'cardinality' relation=[Relation|EString] 'as' newCardinality=Cardinality|EString
;


Attribute returns Attribute:
	Attribute_Impl | AddAttribute;

Relation returns Relation:
	Relation_Impl | AddRelation;



Entity returns Entity:
	Entity_Impl | AddEntity;

Database returns Database:
	RelationalDB | DocumentDB | KeyValueDB | GraphDB | ColumnDB;

GraphAttribute returns GraphAttribute:
	GraphAttribute_Impl | AddGraphAttribute;

GraphEdge returns GraphEdge:
	GraphEdge_Impl | AddGraphEdge;

EString returns ecore::EString:
	STRING | ID;

PrimitiveDataType_Impl returns PrimitiveDataType:
	{PrimitiveDataType}
	('importedNamespace' importedNamespace=EString)?
	'datatype' name=EString
	;

DataTypeItem returns DataTypeItem:
	('importedNamespace' importedNamespace=EString)?
	name=EString ':' type=[DataType|EString] '[' implementation=DataTypeImplementationPackage ']'
	;

DataTypeImplementationPackage returns DataTypeImplementationPackage:
	{DataTypeImplementationPackage}
	location=EString
	;

FreeText returns FreeText:
	{FreeText}
	('importedNamespace' importedNamespace=EString)?
	'FreeText' name=EString
	;

CustomDataType returns CustomDataType:
	{CustomDataType}
	('importedNamespace' importedNamespace=EString)?
	'customdatatype' name=EString '{'
		('elements' '{' elements+=DataTypeItem ( "," elements+=DataTypeItem)* '}' )?
	'}';

Entity_Impl returns Entity:
	('importedNamespace' importedNamespace=EString)?
	'entity' name=EString '{'
		
		(attributes+=Attribute (attributes+=Attribute)*)?
		(relations+=Relation (relations+=Relation)*)?
		('identifer' identifer=EntityIdentifier)?
		('genericList' '{' genericList=[GenericList|EString] '}')?
	'}';
GenericList returns GenericList: 
	Table|Collection|Column|KeyValueElement|GraphNode;

Relation_Impl returns Relation:
	('importedNamespace' importedNamespace=EString)?
	name=EString
	(isContainment?=':')?
	'->'
		(type=[Entity|EString])
		('.' opposite=[Relation|EString])?
		('[' cardinality=Cardinality ']')?
	;

EntityIdentifier returns EntityIdentifier:
	{EntityIdentifier}
	('(' attributes+=[Attribute|EString] ( "," attributes+=[Attribute|EString])* ')' )?
	;


enum Cardinality returns Cardinality:
				zero_one = '0..1' | one = '1' | zero_many = '0..*' | one_many = '*';

EBooleanObject returns ecore::EBooleanObject:
	'true' | 'false';

Table returns Table:
	('importedNamespace' importedNamespace=EString)?
	'table'
	'{'
		name=EString ':' entity=[Entity|EString]
		('db' db=[Database|EString])?
		(indexSpec=IndexSpec)?
		(idSpec=IdSpec)?
	'}';

Collection returns Collection:
	('importedNamespace' importedNamespace=EString)?
	name=EString ':' entity=[Entity|EString]
	;

KeyValueElement returns KeyValueElement:
	('importedNamespace' importedNamespace=EString)?
	key=EString '->' '{'	
		'entity' entity=[Entity|EString]
		('values' '(' values+=[DataType|EString] ( "," values+=[DataType|EString])* ')' )?
	'}';

GraphNode returns GraphNode:
	('importedNamespace' importedNamespace=EString)?
	'node' name=EString '{'
		'entity' entity=[Entity|EString]
		('attributes' '{' attributes+=GraphAttribute ( "," attributes+=GraphAttribute)* '}' )?
	'}';

Column returns Column:
	('importedNamespace' importedNamespace=EString)?
	'column' name=EString '{'
		'entity' entity=[Entity|EString]
		('attributes' '(' attributes+=[Attribute|EString] ( "," attributes+=[Attribute|EString])* ')' )?
	'}';

IndexSpec returns IndexSpec:
	{IndexSpec}
	('importedNamespace' importedNamespace=EString)?
	'index' name=EString '{'
		('attributes' '(' attributes+=[Attribute|EString] ( "," attributes+=[Attribute|EString])* ')' )?
		('references' '(' references+=[Relation|EString] ( "," references+=[Relation|EString])* ')' )?
	'}';

IdSpec returns IdSpec:
	{IdSpec}
	'idSpec' ('(' attributes+=[Attribute|EString] ( "," attributes+=[Attribute|EString])* ')' )?
	;

RelationalDB returns RelationalDB:
	{RelationalDB}
	('importedNamespace' importedNamespace=EString)?
	'relationaldb' name=EString '{'
		('tables' '{' tables+=Table (tables+=Table)* '}' )?
	'}';

DocumentDB returns DocumentDB:
	{DocumentDB}
	('importedNamespace' importedNamespace=EString)?
	'documentdb' name=EString '{'
		('collections' '{' collections+=Collection ( collections+=Collection)* '}' )?
	'}';

KeyValueDB returns KeyValueDB:
	{KeyValueDB}
	('importedNamespace' importedNamespace=EString)?
	'keyvaluedb' name=EString '{'
		('elements' '{' elements+=KeyValueElement ( "," elements+=KeyValueElement)* '}' )?
	'}';

GraphDB returns GraphDB:
	{GraphDB}
	('importedNamespace' importedNamespace=EString)?
	'graphdb' name=EString '{'
		('nodes' '{' nodes+=GraphNode ( "," nodes+=GraphNode)* '}' )?
		('edges' '{' edges+=GraphEdge ( "," edges+=GraphEdge)* '}' )?
	'}';

ColumnDB returns ColumnDB:
	{ColumnDB}
	('importedNamespace' importedNamespace=EString)?
	'columndb' name=EString '{'
		('columns' '{' columns+=Column ( "," columns+=Column)* '}' )?
	'}';

GraphEdge_Impl returns GraphEdge:
	{GraphEdge}
	('importedNamespace' importedNamespace=EString)?
	'edge' name=EString '{'
		('from' from=[GraphNode|EString])?
		('to' to=[GraphNode|EString])?
		('labels' '{' labels+=GraphEdgeLabel ( "," labels+=GraphEdgeLabel)* '}' )?
	'}';

GraphEdgeLabel returns GraphEdgeLabel:
	{GraphEdgeLabel}
	('importedNamespace' importedNamespace=EString)?
	name=EString ':' type=[DataType|EString]
	;
	
AddAttribute returns AddAttribute:
	{AddAttribute}
	('importedNamespace' importedNamespace=EString)?
	'AddAttribute'
	name=EString ':' type=[DataType|EString]
	;

AddGraphEdge returns AddGraphEdge:
	{AddGraphEdge}
	('importedNamespace' importedNamespace=EString)?
	'AddGraphEdge'
	name=EString '{'
		('from' from=[GraphNode|EString])?
		('to' to=[GraphNode|EString])?
		('labels' '{' labels+=GraphEdgeLabel ( "," labels+=GraphEdgeLabel)* '}' )?
	'}';

GraphAttribute_Impl returns GraphAttribute:
	{GraphAttribute}
	('importedNamespace' importedNamespace=EString)?
	name=EString '=' value=[Attribute|EString]?
	;

AddGraphAttribute returns AddGraphAttribute:
	{AddGraphAttribute}
	('importedNamespace' importedNamespace=EString)?
	'AddGraphAttribute'
	name=EString '{'
		('value' value=[Attribute|EString])?
	'}';

AddEntity returns AddEntity:
	('importedNamespace' importedNamespace=EString)?
	'AddEntity'
	name=EString
	'{'
		
		('attributes' '{' attributes+=Attribute ( "," attributes+=Attribute)* '}' )?
		('relations' '{' relations+=Relation ( "," relations+=Relation)* '}' )?
		'identifer' identifer=EntityIdentifier
	'}';

Attribute_Impl returns Attribute:
	{Attribute}
	('importedNamespace' importedNamespace=EString)?
	name=EString ':' type=[DataType|EString]
	;

AddRelation returns AddRelation:
	('importedNamespace' importedNamespace=EString)?
	'AddRelation'
	name=EString 
	(isContainment?=':')?
	'->'
	(type=[Entity|EString])
	('.' opposite=[Relation|EString])?
	('[' cardinality=Cardinality ']')?		
	'}';
