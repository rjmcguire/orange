/**
 * Copyright: Copyright (c) 2010 Jacob Carlborg.
 * Authors: Jacob Carlborg
 * Version: Initial created: Jan 26, 2010
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 */
module orange.serialization.archives.XMLArchive;

version (Tango)
{
	import tango.text.xml.DocPrinter;
	import tango.text.xml.Document;
	import tango.util.Convert : to;
}

import orange.serialization.archives._;
import orange.util._;

private enum ArchiveMode
{
	archiving,
	unarchiving
}

class XMLArchive (U = char) : Archive!(U)
{
	static assert (isChar!(U), format!(`The given type "`, U, `" is not a valid type. Valid types are: "char", "wchar" and "dchar".`));
		
	private struct Tags
	{
		static const DataType structTag = "struct";	
		static const DataType dataTag = "data";
		static const DataType archiveTag = "archive";
		static const DataType arrayTag = "array";
		static const DataType objectTag = "object";
		static const DataType baseTag = "base";
		static const DataType stringTag = "string";
		static const DataType referenceTag = "reference";
		static const DataType pointerTag = "pointer";
		static const DataType associativeArrayTag = "associativeArray";
		static const DataType typedefTag = "typedef";
		static const DataType nullTag = "null";
		static const DataType enumTag = "enum";		
	}

	private struct Attributes
	{
		static const DataType typeAttribute = "type";
		static const DataType versionAttribute = "version";
		static const DataType lengthAttribute = "length";
		static const DataType keyAttribute = "key";
		static const DataType runtimeTypeAttribute = "runtimeType";
		static const DataType idAttribute = "id";
		static const DataType keyTypeAttribute = "keyType";
		static const DataType valueTypeAttribute = "valueType";
	}
	
	private
	{
		DataType archiveType = "org.dsource.orange.xml";
		DataType archiveVersion = "0.1";
		
		Document!(U) doc;
		doc.Node lastElement;
		DocPrinter!(U) printer;
		doc.Node lastElementSaved;
		
		bool hasBegunArchiving;
		bool hasBegunUnarchiving;
		
		DataType[void*] archivedReferences;
		void*[DataType] unarchivedReferences;
		
		size_t idCounter;
	}
	
	this ()
	{
		doc = new Document!(U);
	}
	
	public void beginArchiving ()
	{
		if (!hasBegunArchiving)
		{
			doc.header;
			lastElement = doc.tree.element(null, Tags.archiveTag)
				.attribute(null, Attributes.typeAttribute, archiveType)
				.attribute(null, Attributes.versionAttribute, archiveVersion);
			lastElement = lastElement.element(null, Tags.dataTag);
			
			hasBegunArchiving = true;
		}		
	}
	
	public void beginUnarchiving (DataType data)
	{
		if (!hasBegunUnarchiving)
		{
			doc.parse(data);	
			hasBegunUnarchiving = true;
			
			auto set = doc.query[Tags.archiveTag][Tags.dataTag];

			if (set.nodes.length == 1)
				lastElement = set.nodes[0];
			
			else if (set.nodes.length == 0)
				throw new ArchiveException(errorMessage!(ArchiveMode.unarchiving) ~ `The "` ~ to!(string)(Tags.dataTag) ~ `" tag could not be found.`, __FILE__, __LINE__);
			
			else
				throw new ArchiveException(errorMessage!(ArchiveMode.unarchiving) ~ `There were more than one "` ~ to!(string)(Tags.dataTag) ~ `" tag.`, __FILE__, __LINE__);
		}
	}
	
	public DataType data ()
	{
		if (!printer)
			printer = new DocPrinter!(U);
		
		return printer.print(doc);
	}
	
	public void reset ()
	{
		hasBegunArchiving = false;
		hasBegunUnarchiving = false;
		idCounter = 0;
		doc.reset;
	}
	
	private void begin ()
	{
		lastElementSaved = lastElement;
	}
	
	private void end ()
	{
		lastElement = lastElementSaved;
	}
	
	public void archive (T) (T value, DataType key, void delegate () dg = null)
	{
		if (!hasBegunArchiving)
			beginArchiving();
		
		restore(lastElement) in {
			bool callDelegate = true;
			
			static if (isTypeDef!(T))
				archiveTypeDef(value, key);
			
			else static if (isObject!(T))
				archiveObject(value, key, callDelegate);
			
			else static if (isStruct!(T))
				archiveStruct(value, key);
			 
			else static if (isString!(T))
				archiveString(value, key);
			
			else static if (isArray!(T))
				archiveArray(value, key);
			
			else static if (isAssociativeArray!(T))
				archiveAssociativeArray(value, key);
			
			else static if (isPrimitive!(T))
				archivePrimitive(value, key);
			
			else static if (isPointer!(T))
				archivePointer(value, key, callDelegate);
			
			else static if (isEnum!(T))
				archiveEnum(value, key);
			
			else
				static assert(false, format!(`The type "`, T, `" cannot be archived.`));
			
			if (callDelegate && dg)
				dg();
		};
	}
	
	private void archiveObject (T) (T value, DataType key, ref bool callDelegate)
	{		
		if (!value)
		{
			lastElement.element(null, Tags.nullTag)
			.attribute(null, Attributes.typeAttribute, toDataType(T.stringof))
			.attribute(null, Attributes.keyAttribute, key);
			callDelegate = false;
		}
		
		else if (auto reference = getArchivedReference(value))
		{
			archiveReference(key, reference);
			callDelegate = false;
		}
		
		else
		{
			DataType id = nextId;
			
			lastElement = lastElement.element(null, Tags.objectTag)
			.attribute(null, Attributes.runtimeTypeAttribute, toDataType(value.classinfo.name))
			.attribute(null, Attributes.typeAttribute, toDataType(T.stringof))
			.attribute(null, Attributes.keyAttribute, key)
			.attribute(null, Attributes.idAttribute, id);
			
			addArchivedReference(value, id);
		}
	}

	private void archiveStruct (T) (T value, DataType key)
	{
		lastElement = lastElement.element(null, Tags.structTag)
		.attribute(null, Attributes.typeAttribute, toDataType(T.stringof))
		.attribute(null, Attributes.keyAttribute, key);
	}
	
	private void archiveString (T) (T value, DataType key)
	{
		lastElement.element(null, Tags.stringTag, toDataType(value))
		.attribute(null, Attributes.typeAttribute, toDataType(BaseTypeOfArray!(T).stringof))
		.attribute(null, Attributes.keyAttribute, key);
	}

	private void archiveArray (T) (T value, DataType key)
	{		
		lastElement = lastElement.element(null, Tags.arrayTag)		
		.attribute(null, Attributes.typeAttribute, toDataType(BaseTypeOfArray!(T).stringof))
		.attribute(null, Attributes.lengthAttribute, toDataType(value.length))
		.attribute(null, Attributes.keyAttribute, key);
	}

	private void archiveAssociativeArray (T) (T value, DataType key)
	{
		lastElement = lastElement.element(null, Tags.associativeArrayTag)		
		.attribute(null, Attributes.keyTypeAttribute, toDataType(KeyTypeOfAssociativeArray!(T).stringof))
		.attribute(null, Attributes.valueTypeAttribute, toDataType(ValueTypeOfAssociativeArray!(T).stringof))
		.attribute(null, Attributes.lengthAttribute, toDataType(value.length))
		.attribute(null, Attributes.keyAttribute, key);
	}

	private void archivePointer (T) (T value, DataType key, ref bool callDelegate)
	{
		if (auto reference = getArchivedReference(value))
		{
			archiveReference(key, reference);
			callDelegate = false;
		}
		
		else
		{
			DataType id = nextId;
			
			lastElement = lastElement.element(null, Tags.pointerTag)
			.attribute(null, Attributes.keyAttribute, key)
			.attribute(null, Attributes.idAttribute, id);
			
			addArchivedReference(value, id);
		}
	}
	
	private void archiveEnum (T) (T value, DataType key)
	{
		lastElement.element(null, Tags.enumTag, toDataType(value))
		.attribute(null, Attributes.typeAttribute, toDataType(T.stringof))
		.attribute(null, Attributes.keyAttribute, key);
	}

	private void archivePrimitive (T) (T value, DataType key)
	{
		lastElement.element(null, toDataType(T.stringof), toDataType(value))
		.attribute(null, Attributes.keyAttribute, key);
	}
	
	private void archiveTypeDef (T) (T value, DataType key)
	{
		lastElement = lastElement.element(null, Tags.typedefTag)
		.attribute(null, Attributes.typeAttribute, toDataType(BaseTypeOfTypeDef!(T).stringof));
		.attribute(null, Attributes.key, key);
	}
	
	public T unarchive (T) (DataType key, T delegate (T) dg = null)
	{
		if (!hasBegunUnarchiving)
			beginUnarchiving(data);
		
		return restore!(T)(lastElement) in {
			T value;
			
			bool callDelegate = true;
			
			static if (isTypeDef!(T))
				value = unarchiveTypeDef!(T)(key);
			
			else static if (isObject!(T))
				value = unarchiveObject!(T)(key, callDelegate);				

			else static if (isStruct!(T))
				value = unarchiveStruct!(T)(key);
			
			else static if (isString!(T))
				value = unarchiveString!(T)(key);
			 
			else static if (isArray!(T))
				value = unarchiveArray!(T)(key);

			else static if (isAssociativeArray!(T))
				value = unarchiveAssociativeArray!(T)(key);

			else static if (isPrimitive!(T))
				value = unarchivePrimitive!(T)(key);

			else static if (isPointer!(T))
				value = unarchivePointer!(T)(key, callDelegate);
			
			else static if (isEnum!(T))
				value = unarchiveEnum!(T)(key);
			
			else
				static assert(false, format!(`The type "`, T, `" cannot be unarchived.`));

			if (callDelegate && dg)
				return dg(value);
			
			return value;
		};
	}

	private T unarchiveObject (T) (DataType key, ref bool callDelegate)
	{			
		DataType id = unarchiveReference(key);
		
		if (auto reference = getUnarchivedReference!(T)(id))
		{
			callDelegate = false;
			return *reference;
		}
		
		auto tmp = getElement(Tags.objectTag, key, Attributes.keyAttribute, false);
		
		if (!tmp)
		{
			lastElement = getElement(Tags.nullTag, key);
			callDelegate = false;
			return null;
		}
		
		lastElement = tmp;
		
		auto runtimeType = getValueOfAttribute(Attributes.runtimeTypeAttribute);
		auto name = fromDataType!(string)(runtimeType);
		id = getValueOfAttribute(Attributes.idAttribute);
				
		T result;
		
		static if (is(typeof(T._ctor)))
		{
			ParameterTupleOf!(typeof(T._ctor)) params;			
			result = factory!(T, typeof(params))(name, params);
		}
		
		else
			 result = factory!(T)(name);
		
		addUnarchivedReference(result, id);
		
		return result;
	}

	private T unarchiveStruct (T) (DataType key)
	{
		lastElement = getElement(Tags.structTag, key);
		
		return T.init;
	}
	
	private T unarchiveString (T) (DataType key)
	{
		return fromDataType!(T)(getElement(Tags.stringTag, key).value);
	}

	private T unarchiveArray (T) (DataType key)
	{			
		T value;
		
		lastElement = getElement(Tags.arrayTag, key);
		auto length = getValueOfAttribute(Attributes.lengthAttribute);
		value.length = fromDataType!(size_t)(length);
		
		return value;
	}

	private T unarchiveAssociativeArray (T) (DataType key)
	{		
		lastElement = getElement(Tags.associativeArrayTag, key);
		
		return T.init;
	}

	private T unarchivePointer (T) (DataType key, ref bool callDelegate)
	{
		DataType id = unarchiveReference(key);
		
		if (auto reference = getUnarchivedReference!(T)(id))
		{
			callDelegate = false;
			return *reference;
		}

		lastElement = getElement(Tags.pointerTag, key);
		id = getValueOfAttribute(Attributes.idAttribute);
				
		T result = new BaseTypeOfPointer!(T);
		
		addUnarchivedReference(result, id);
		
		return result;
	}
	
	private T unarchiveEnum (T) (DataType key)
	{
		return fromDataType!(T)(getElement(Tags.enumTag, key).value);
	}

	private T unarchivePrimitive (T) (DataType key)
	{		
		return fromDataType!(T)(getElement(toDataType(T.stringof), key).value);
	}
	
	private T unarchiveTypeDef (T) (DataType key)
	{
		lastElement = getElement(Tags.typedefTag, key);
		
		return T.init;
	}
	
	public AssociativeArrayVisitor!(KeyTypeOfAssociativeArray!(T), ValueTypeOfAssociativeArray!(T)) unarchiveAssociativeArrayVisitor (T)  ()
	{
		return AssociativeArrayVisitor!(KeyTypeOfAssociativeArray!(T), ValueTypeOfAssociativeArray!(T))(this);
	}
	
	public void archiveBaseClass (T : Object) (DataType key)
	{
		lastElement = lastElement.element(null, Tags.baseTag)
		.attribute(null, Attributes.typeAttribute, toDataType(T.stringof))
		.attribute(null, Attributes.keyAttribute, key);
	}
	
	public void unarchiveBaseClass (T : Object) (DataType key)
	{
		lastElement = getElement(Tags.baseTag, key);
	}
	
	template errorMessage (ArchiveMode mode = ArchiveMode.archiving)
	{
		static if (mode == ArchiveMode.archiving)
			const errorMessage = "Could not continue archiving due to unrecognized data format: ";
			
		else static if (mode == ArchiveMode.unarchiving)
			const errorMessage = "Could not continue unarchiving due to unrecognized data format: ";
	}
	
	private doc.Node getElement (DataType tag, DataType key, DataType attribute = Attributes.keyAttribute, bool throwOnError = true)
	{
		auto set = lastElement.query[tag].attribute((doc.Node node) {			
			if (node.name == attribute && node.value == key)
				return true;
			
			return false;
		});
		
		if (set.nodes.length == 1)
			return set.nodes[0].parent;
		
		else
		{
			if (throwOnError)
			{
				if (set.nodes.length == 0)
					throw new ArchiveException(`Could not find an element "` ~ to!(string)(tag) ~ `" with the attribute "` ~ to!(string)(Attributes.keyAttribute) ~ `" with the value "` ~ to!(string)(key) ~ `".`, __FILE__, __LINE__);
				
				else
					throw new ArchiveException(`Could not unarchive the value with the key "` ~ to!(string)(key) ~ `" due to malformed data.`, __FILE__, __LINE__);
			}
			
			return null;
		}		
	}
	
	private DataType getValueOfAttribute (DataType attribute)
	{
		auto set = lastElement.query.attribute(attribute);
		
		if (set.nodes.length == 1)
			return set.nodes[0].value;
		
		else if (set.nodes.length == 0)
			throw new ArchiveException(`Could not find the attribute "` ~ to!(string)(attribute) ~ `".`, __FILE__, __LINE__);
		
		else
			throw new ArchiveException(`Could not unarchive the value of the attribute "` ~ to!(string)(attribute) ~ `" due to malformed data.`, __FILE__, __LINE__);
	}
	
	private void addArchivedReference (T) (T value, DataType id)
	{
		static assert(isReference!(T), format!(`The given type "`, T, `" is not a reference type, i.e. object or pointer.`));
		
		archivedReferences[cast(void*) value] = id;
	}
	
	private void addUnarchivedReference (T) (T value, DataType id)
	{
		static assert(isReference!(T), format!(`The given type "`, T, `" is not a reference type, i.e. object or pointer.`));
		
		unarchivedReferences[id] = cast(void*) value;
	}
	
	private DataType getArchivedReference (T) (T value)
	{
		if (auto tmp = cast(void*) value in archivedReferences)
			return *tmp;
		
		return null;
	}
	
	private T* getUnarchivedReference (T) (DataType id)
	{
		if (auto reference = id in unarchivedReferences)
			return cast(T*) reference;
		
		return null;
	}
	
	private DataType nextId ()
	{
		return toDataType(idCounter++);
	}
	
	private void archiveReference (DataType key, DataType id)
	{		
		lastElement.element(null, Tags.referenceTag, id)
		.attribute(null, Attributes.keyAttribute, key);
	}
	
	private DataType unarchiveReference (DataType key)
	{	
		auto element = getElement(Tags.referenceTag, key, Attributes.keyAttribute, false);
		
		if (element)
			return element.value;
		
		return cast(DataType) null;
	}
	
	private struct AssociativeArrayVisitor (Key, Value)
	{
		private XMLArchive archive;
		
		static AssociativeArrayVisitor opCall (XMLArchive archive)
		{
			AssociativeArrayVisitor aai;
			aai.archive = archive;
			
			return aai;
		}
		
		int opApply(int delegate(ref Key, ref Value) dg)
		{  
			int result;
			
			foreach (node ; archive.lastElement.children)
			{
				restore(archive.lastElement) in {
					archive.lastElement = node;
					
					if (node.attributes.exist)
					{
						Key key = to!(Key)(archive.getValueOfAttribute(Attributes.keyAttribute));
						Value value = to!(Value)(node.value);
						
						result = dg(key, value);	
					}		
				};
				
				if (result)
					break;
			}
			
			return result;
		}
	}
}