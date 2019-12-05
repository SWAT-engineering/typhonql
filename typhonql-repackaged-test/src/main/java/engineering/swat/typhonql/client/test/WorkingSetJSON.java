package engineering.swat.typhonql.client.test;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.List;
import java.util.Map;

import com.fasterxml.jackson.core.JsonGenerator;
import com.fasterxml.jackson.core.JsonParseException;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JavaType;
import com.fasterxml.jackson.databind.JsonMappingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.module.jsonSchema.JsonSchema;
import com.fasterxml.jackson.module.jsonSchema.JsonSchemaGenerator;

import nl.cwi.swat.typhonql.workingset.Entity;
import nl.cwi.swat.typhonql.workingset.EntityRef;
import nl.cwi.swat.typhonql.workingset.WorkingSet;

public class WorkingSetJSON {
	private static ObjectMapper mapper = new ObjectMapper();
	
	static {
		//mapper.configure(DeserializationFeature.
		mapper.configure(JsonGenerator.Feature.AUTO_CLOSE_TARGET, false);
		mapper.canDeserialize(mapper.getTypeFactory().constructSimpleType(EntityRef.class, new JavaType[0]));
		mapper.canSerialize(EntityRef.class);
		/*SimpleModule module = new SimpleModule();
		module.addDeserializer(EntityRef.class, new FieldValueDeserializer());
		mapper.registerModule(module);
		*/
	}
	
	public static WorkingSet fromJSON(InputStream is) throws IOException {
		try {
			Map<String, List<Entity>> map = mapper.readValue(is, new TypeReference<Map<String, List<Entity>>>() {});
			return new WorkingSet(map);
		} catch (JsonParseException e) {
			throw new RuntimeException(e);
		} catch (JsonMappingException e) {
			throw new RuntimeException(e);
		}
		
	}
	
	public static void toJSON(WorkingSet ws, OutputStream os) throws IOException {
		try {
			mapper.writeValue(os, ws.getMap());
		} catch (JsonProcessingException e) {
			throw new RuntimeException(e);
		}
	}
	
	public static String getSchema() {
		ObjectMapper mapper = new ObjectMapper();
		// configure mapper, if necessary, then create schema generator
		JsonSchemaGenerator schemaGen = new JsonSchemaGenerator(mapper);
		try {
			JsonSchema schema = schemaGen.generateSchema(
					mapper.getTypeFactory().constructMapType(Map.class, 
							mapper.getTypeFactory().constructSimpleType(String.class, new JavaType[0]),
							mapper.getTypeFactory().constructParametricType(List.class, Entity.class)));
			return mapper.writerWithDefaultPrettyPrinter().writeValueAsString(schema);
		} catch (JsonMappingException e) {
			throw new RuntimeException(e);
		} catch (JsonProcessingException e) {
			throw new RuntimeException(e);
		}
		
	}
}