package mesh
{
	import collections.HashMap;
	import collections.HashSet;
	import collections.ISet;
	import collections.ImmutableSet;
	
	import flash.utils.Proxy;
	import flash.utils.describeType;
	import flash.utils.getDefinitionByName;
	import flash.utils.getQualifiedClassName;
	import flash.utils.getQualifiedSuperclassName;
	
	import mesh.adaptors.ServiceAdaptor;
	import mesh.associations.BelongsToRelationship;
	import mesh.associations.HasManyDefinition;
	import mesh.associations.HasOneDefinition;
	import mesh.associations.AssociationDefinition;
	import mesh.core.reflection.clazz;
	import mesh.core.reflection.newInstance;
	
	import mx.utils.StringUtil;

	public class EntityDescription
	{
		private static const RELATIONSHIPS:Object = {
			HasMany: HasManyDefinition,
			HasOne: HasOneDefinition,
			BelongsTo: BelongsToRelationship
		};
		
		private static const DESCRIPTIONS:HashMap = new HashMap();
		
		private var _description:XML;
		private var _metadata:XMLList;
		
		private var _relationships:HashSet = new HashSet();
		private var _propertyToRelationship:HashMap = new HashMap();
		
		private var _aggregates:HashSet = new HashSet();
		private var _propertyToAggregate:HashMap = new HashMap();
		
		private var _adaptor:ServiceAdaptor;
		
		private var _ignoredProperties:HashSet = new HashSet();
		
		public function EntityDescription(entityType:Class)
		{
			_entityType = entityType;
			_description = describeType(entityType);
			_metadata = _description..metadata;
			
			parseAdaptor();
			parseAggregates();
			parseFactory();
			parseIgnore();
			parseRelationships();
			parseVOType();
		}
		
		public static function describe(entity:Object):EntityDescription
		{
			if (!(entity is Class)) {
				entity = clazz(entity);
			}
			
			if (!DESCRIPTIONS.containsKey(entity)) {
				DESCRIPTIONS.put(entity, new EntityDescription(entity as Class));
			}
			
			return DESCRIPTIONS.grab(entity);
		}
		
		public function addAggregates(...aggregates):void
		{
			for each (var aggregate:Aggregate in aggregates) {
				_aggregates.add(aggregate);
				_propertyToAggregate.put(aggregate.property, aggregate);
				
				for each (var mapping:String in aggregate.mappings) {
					_propertyToAggregate.put(mapping, aggregate);
				}
			}
		}
		
		public function addRelationships(...relationships):void
		{
			for each (var relationship:AssociationDefinition in relationships) {
				_relationships.add(relationship);
				_propertyToRelationship.put(relationship.property, relationship);
			}
		}
		
		public function equals(description:EntityDescription):Boolean
		{
			return description != null && entityType == description.entityType;
		}
		
		public function getAggregateForProperty(property:String):Aggregate
		{
			return _propertyToAggregate.grab(property);
		}
		
		public function getRelationshipForProperty(property:String):AssociationDefinition
		{
			return _propertyToRelationship.grab(property);
		}
		
		public function hashCode():Object
		{
			return _entityType;
		}
		
		private function parseAggregates():void
		{
			var aggregates:Array = [];
			for each (var composedOfXML:XML in _metadata.(@name == "ComposedOf")) {
				var options:Object = {};
				for each (var argXML:XML in composedOfXML..arg) {
					options[argXML.@key] = argXML.@value.toString();
				}
				options.mapping = StringUtil.trimArrayElements(options.mapping, ",").split(",");
				
				addAggregates(new Aggregate(entityType, options.hasOwnProperty("property") ? options.property : composedOfXML.parent().@name, getDefinitionByName(options.hasOwnProperty("type") ? options.type : composedOfXML.parent().@type) as Class, options));
			}
			
			var parent:Class = parentEntityType;
			while (parent != null) {
				var description:EntityDescription = describe(parent);
				addAggregates.apply(null, description.aggregates.toArray());
				parent = description.parentEntityType;
			}
		}
		
		private function parseAdaptor():void
		{
			for each (var adaptorXML:XML in _metadata.(@name == "ServiceAdaptor")) {
				var options:Object = {};
				
				for each (var argXML:XML in adaptorXML..arg) {
					options[argXML.@key] = argXML.@value.toString();
				}
				
				_adaptor = entityType[adaptorXML.parent().@name];
				if (_adaptor == null) {
					_adaptor = ServiceAdaptor( newInstance(getDefinitionByName(adaptorXML.parent().@type) as Class, entityType, options) );
				}
				break;
			}
			
			var parent:Class = parentEntityType;
			while (_adaptor == null && parent != null) {
				var description:EntityDescription = describe(parent);
				_adaptor = description.adaptor;
				parent = description.parentEntityType;
			}
		}
		
		private function parseFactory():void
		{
			for each (var factoryXML:XML in _metadata.(@name == "Factory")) {
				_factoryMethod = factoryXML.parent().@name;
				break;
			}
			
			var parent:Class = parentEntityType;
			while (_factoryMethod == null && parent != null) {
				var description:EntityDescription = describe(parent);
				_factoryMethod = description.factoryMethod;
				parent = description.parentEntityType;
			}
		}
		
		private function parseIgnore():void
		{
			for each (var ignoreXML:XML in _metadata.(@name == "Ignore")) {
				var options:Object = {};
				for each (var argXML:XML in ignoreXML..arg) {
					options[argXML.@key] = argXML.@value.toString();
				}
				
				if (!options.hasOwnProperty("property") && ["accessor", "variable"].indexOf(ignoreXML.parent().name().toString()) != -1) {
					options.property = ignoreXML.parent().@name.toString();
				}
				
				options.properties = options.hasOwnProperty("properties") ? StringUtil.trimArrayElements(options.properties, ",").split(",") : [];
				
				if (options.hasOwnProperty("property")) {
					options.properties.push(options.property);
				}
				
				_ignoredProperties.addAll(options.properties);
			}
			
			var parent:Class = parentEntityType;
			while (parent != null) {
				var description:EntityDescription = describe(parent);
				_ignoredProperties.addAll(description.ignoredProperties);
				parent = description.parentEntityType;
			}
		}
		
		private function parseRelationships():void
		{
			for each (var relationshipXML:XML in _metadata.(@name == "HasOne" || @name == "HasMany" || @name == "BelongsTo")) {
				var kind:String = relationshipXML.@name;
				var options:Object = {};
				
				for each (var argXML:XML in relationshipXML..arg) {
					options[argXML.@key] = argXML.@value.toString();
				}
				
				if (!options.hasOwnProperty("type")) {
					options.type = relationshipXML.parent().@type;
				}
				options.type = getDefinitionByName(options.type) as Class;
				
				// try to grab the property auto-magically.
				if (!options.hasOwnProperty("property")) {
					// first try to see if there's an accessor we can use.
					if (relationshipXML.parent().name() == "accessor") {
						options.property = relationshipXML.parent().@name;
					}
				}
				
				var ownerType:Class = entityType;
				if (relationshipXML.parent().name() == "accessor") {
					ownerType = getDefinitionByName(relationshipXML.parent().@declaredBy) as Class;
				}
				
				addRelationships( newInstance(RELATIONSHIPS[kind], ownerType, options.property, options.type, options) );
			}
			
			var parent:Class = parentEntityType;
			while (parent != null) {
				var description:EntityDescription = describe(parent);
				addRelationships.apply(null, description.relationships.toArray());
				parent = description.parentEntityType;
			}
		}
		
		private function parseVOType():void
		{
			for each (var voXML:XML in _metadata.(@name == "VO")) {
				_voType = getDefinitionByName(voXML.parent().@type) as Class;
				break;
			}
			
			var parent:Class = parentEntityType;
			while (_voType == null && parent != null) {
				var description:EntityDescription = describe(parent);
				_voType = description.voType;
				parent = description.parentEntityType;
			}
		}
		
		public function newEntity(data:Object):Entity
		{
			var entity:Entity = factoryMethod == null || entityType[factoryMethod] == null ? newInstance(entityType) as Entity : entityType[factoryMethod](data);
			return entity;
		}
		
		public function get aggregates():ISet
		{
			return new ImmutableSet(_aggregates);
		}
		
		public function get relationships():ISet
		{
			return new ImmutableSet(_relationships);
		}
		
		public function get adaptor():ServiceAdaptor
		{
			return _adaptor;
		}
		
		private var _factoryMethod:String;
		public function get factoryMethod():String
		{
			return _factoryMethod;
		}
		
		private var _entityType:Class;
		public function get entityType():Class
		{
			return _entityType;
		}
		
		public function get ignoredProperties():ISet
		{
			return _ignoredProperties;
		}
		
		private var _parentEntityType:*;
		public function get parentEntityType():Class
		{
			if (_parentEntityType === undefined) {
				_parentEntityType = getDefinitionByName(getQualifiedSuperclassName(entityType)) as Class;
				
				if (_parentEntityType == Proxy) {
					_parentEntityType = null;
				}
			}
			return _parentEntityType;
		}
		
		private var _properties:HashSet;
		public function get properties():ISet
		{
			if (_properties == null) {
				_properties = new HashSet(["id"]);
				
				for each (var aggregate:Aggregate in aggregates) {
					_properties.addAll(aggregate.properties);
				}
				
				for each (var relationship:AssociationDefinition in relationships) {
					_properties.addAll(relationship.properties);
				}
				
				var entityPath:String = getQualifiedClassName(Entity);
				for each (var accessorXML:XML in _description..accessor.(@declaredBy != entityPath && @declaredBy != "Class" && @declaredBy != "Object")) {
					_properties.add(accessorXML.@name.toString());
				}
			}
			return _properties;
		}
		
		private var _voType:Class;
		public function get voType():Class
		{
			return _voType;
		}
	}
}