package nl.cwi.swat.typhonql.client.resulttable;

import java.io.IOException;
import java.io.OutputStream;
import java.util.List;
import java.util.stream.Stream;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonInclude;

import io.usethesource.vallang.type.Type;
import nl.cwi.swat.typhonql.client.JsonSerializableResult;

public class StreamingResultTable implements JsonSerializableResult {

	private final List<String> columnNames;
	private final Stream<Object[]> values;
	@JsonInclude(JsonInclude.Include.NON_NULL)
	private String warnings = null;

	public StreamingResultTable(List<String> columnNames, Stream<Object[]> values) {
		this.columnNames = columnNames;
		this.values = values;
	}
	
	public List<String> getColumnNames() {
		return columnNames;
	}
	
	public Stream<Object[]> getValues() {
		return values;
	}

	@Override
	public void serializeJSON(OutputStream target) throws IOException {
		QLSerialization.mapper.writeValue(target, this);
	}

	@Override
	public String toString() {
		return "ResultTable [\ncolumnNames=" + columnNames + ",\n values=" + values + "\n]";
	}
	
	@Override
	@JsonIgnore
	public Type getType() {
		return TF.externalType(TF.valueType());
	}
	
	@Override
	public void addWarnings(String warnings) {
		this.warnings = warnings;
	}
	
	@Override
	@JsonIgnore
	public boolean isAnnotatable() {
        return false;
    }
}
