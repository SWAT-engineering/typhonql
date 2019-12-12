package nl.cwi.swat.typhonql.backend;

import org.bson.Document;

import com.mongodb.client.MongoCursor;
import com.mongodb.client.MongoIterable;

public class MongoDBIterator implements ResultIterator {
	private MongoIterable<Document> results;
	private MongoCursor<Document> cursor = null;
	private Document current = null;

	public MongoDBIterator(MongoIterable<Document> results) {
		this.results = results;
		this.cursor = results.cursor();
	}

	@Override
	public void nextResult() {
		this.current = cursor.next();
	}

	@Override
	public boolean hasNextResult() {
		return cursor.hasNext();
	}

	@Override
	public String getCurrentId(String type) {
		return current.getString("_id");
	}

	@Override
	public Object getCurrentField(String type, String name) {
		// TODO TEMPORARY!!!!!
		//return current.get(type + "." + name);
		return current.get(name);
	}

	@Override
	public void beforeFirst() {
		cursor = results.cursor();
	}

}
