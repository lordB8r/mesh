package mesh.model
{
	import flash.errors.IllegalOperationError;
	import flash.events.EventDispatcher;
	
	import mesh.core.inflection.humanize;
	import mesh.core.object.copy;
	import mesh.core.reflection.Type;
	import mesh.mesh_internal;
	import mesh.model.associations.Association;
	import mesh.model.associations.HasManyAssociation;
	import mesh.model.associations.HasOneAssociation;
	import mesh.model.store.Data;
	import mesh.model.store.Records;
	import mesh.model.store.Store;
	import mesh.model.validators.Errors;
	import mesh.model.validators.Validator;
	import mesh.operations.Operation;
	import mesh.operations.ResultOperationEvent;
	
	import mx.events.PropertyChangeEvent;
	
	use namespace mesh_internal;
	
	/**
	 * A record.
	 * 
	 * @author Dan Schultz
	 */
	public class Record extends EventDispatcher
	{
		private var _associations:Associations;
		private var _aggregates:Aggregates;
		
		/**
		 * Constructor.
		 * 
		 * @param values A hash of values to set on the record.
		 */
		public function Record(values:Object = null)
		{
			super();
			
			_associations = new Associations(this);
			_aggregates = new Aggregates(this);
			
			copy(values, this);
			addEventListener(PropertyChangeEvent.PROPERTY_CHANGE, handlePropertyChange);
		}
		
		/**
		 * @copy mesh.model.Aggregates#add()
		 */
		protected function aggregate(property:String, type:Class, mappings:Array):void
		{
			_aggregates.add(property, type, mappings);
		}
		
		/**
		 * Maps a has-one association to a property on this record.
		 * 
		 * @param property The property that owns the association.
		 * @param query The query to retrieve data for the association.
		 * @param options Any options to configure the association.
		 * @return The association object.
		 */
		protected function hasOne(property:String, options:Object = null):void
		{
			_associations.map(property, new HasOneAssociation(this, property, options));
		}
		
		/**
		 * Maps up a has-many association to a property on this record.
		 * 
		 * @param property The property that owns the association.
		 * @param query The query to retrieve data for the association.
		 * @param options Any options to configure the association.
		 * @return The association object.
		 */
		protected function hasMany(property:String, options:Object = null):void
		{
			var association:HasManyAssociation = new HasManyAssociation(this, property, options);
			this[property] = association;
			_associations.map(property, association);
		}
		
		/**
		 * Checks if two records are equal.  By default, two records are equal
		 * when they are of the same type, and their ID's are the same.
		 * 
		 * @param obj The record to check.
		 * @return <code>true</code> if the records are equal.
		 */
		public function equals(obj:Object):Boolean
		{
			return obj != null && (this === obj || (reflect.clazz == obj.reflect.clazz && id === obj.id));
		}
		
		private function handlePropertyChange(event:PropertyChangeEvent):void
		{
			propertyChanged(event.property.toString(), event.oldValue, event.newValue);
		}
		
		/**
		 * Returns a generated hash value for this record.  Two records that represent
		 * the same data should return the same hash code.
		 * 
		 * @return A hash value.
		 */
		public function hashCode():Object
		{
			return id;
		}
		
		private function indexed():void
		{
			initializeAssociations();
		}
		
		private function initializeAssociations():void
		{
			for each (var association:Association in associations) {
				association.initialize();
			}
		}
		
		/**
		 * Runs the validations defined for this record and returns <code>true</code> if any
		 * validations failed.
		 * 
		 * @return <code>true</code> if any validations failed.
		 * 
		 * @see #isValid()
		 * @see #validate()
		 */
		public function isInvalid():Boolean
		{
			return !isValid();
		}
		
		/**
		 * Runs the validations defined for this record and returns <code>true</code> if all
		 * validations passed.
		 * 
		 * @return <code>true</code> if all validations passed.
		 * 
		 * @see #isInvalid()
		 * @see #validate()
		 */
		public function isValid():Boolean
		{
			return validate().length == 0;
		}
		
		/**
		 * Loads the data for this record. If the data has already been loaded, then it will not
		 * be reloaded. Use <code>refresh()</code> to reload the data.
		 * 
		 * @see #refresh()
		 * @return This instance.
		 */
		public function load():*
		{
			if (!isLoaded) {
				refresh();
			}
			return this;
		}
		
		/**
		 * Marks a property on the record as being dirty. This method allows sub-classes to manually 
		 * manage when a property changes.
		 * 
		 * @param property The property that was changed.
		 * @param oldValue The property's old value.
		 * @param newValue The property's new value.
		 */
		protected function propertyChanged(property:String, oldValue:Object, newValue:Object):void
		{
			if (!associations.isAssociation(property)) {
				changes.changed(property, oldValue, newValue);
				_aggregates.changed(property);
			}
		}
		
		/**
		 * Reloads the data for this record. Unlike <code>load()</code>, this method will load
		 * the data for the record even if it's already been retrieved.
		 * 
		 * @see #load()
		 * @return This instance.
		 */
		public function refresh():*
		{
			loadOperation.queue();
			loadOperation.execute();
			return this;
		}
		
		/**
		 * @private
		 */
		override public function toString():String
		{
			return humanize(reflect.className);
		}
		
		/**
		 * Runs the validations defined on this record and returns the set of errors for
		 * any validations that failed. If all validations passed, this method returns an
		 * empty array.
		 * 
		 * <p>
		 * Calling this method will also populate the <code>Record.errors</code> property with
		 * the validation results.
		 * </p>
		 * 
		 * @see #isInvalid()
		 * @see #isValid()
		 * @see #errors
		 */
		private function validate():Array
		{
			errors.clear();
			
			for (var reflection:Type = reflect; reflection != null && reflection.clazz != Record; reflection = reflection.parent) {
				var validations:Object = reflection.clazz["validate"];
				for (var property:String in validations) {
					for each (var validation:Object in validations[property]) {
						var ValidatorClass:Class = validation.validator;
						validation.property = property;
						(new ValidatorClass(validation) as Validator).validate(this);
					}
				}
			}
			return errors.toArray();
		}
		
		/**
		 * The hash the associations defined on this record. The associations hash is defined as 
		 * key-value pairs where the key is the property the associaiton is defined on, and the
		 * value is the association object.
		 */
		public function get associations():Associations
		{
			return _associations;
		}
		
		private var _changes:Changes;
		/**
		 * @copy Changes
		 */
		public function get changes():Changes
		{
			if (_changes == null) {
				_changes = new Changes(this);
			}
			return _changes;
		}
		
		private var _data:Data;
		/**
		 * The data for this record.
		 */
		mesh_internal function get data():Data
		{
			return _data;
		}
		mesh_internal function set data(value:Data):void
		{
			_data = value;
			_data.transferValues(this);
		}
		
		private var _errors:Errors;
		/**
		 * A set of <code>ValidationResult</code>s that failed during the last call to 
		 * <code>validate()</code>.
		 * 
		 * @see #validate()
		 */
		public function get errors():Errors
		{
			if (_errors == null) {
				_errors = new Errors(this);
			}
			return _errors;
		}
		
		private var _id:*;
		/**
		 * An object that represents the ID for this record.
		 */
		public function get id():*
		{
			return _id;
		}
		public function set id(value:*):void
		{
			_id = value;
		}
		
		private var _isLoaded:Boolean;
		/**
		 * Checks if the data for this record has been loaded.
		 */
		public function get isLoaded():Boolean
		{
			return _isLoaded;
		}
		
		private var _loadOperation:Operation;
		/**
		 * The operation that is used to load data for this record.
		 */
		public function get loadOperation():Operation
		{
			if (_loadOperation == null) {
				_loadOperation = store.dataSource.retrieve(reflect.clazz, id);
				_loadOperation.addEventListener(ResultOperationEvent.RESULT, function(event:ResultOperationEvent):void
				{
					store.materialize(event.data);
					_isLoaded = true;
				});
			}
			return _loadOperation;
		}
		
		private var _reflect:Type;
		/**
		 * A reflection that contains the properties, methods and metadata defined on this
		 * record.
		 */
		public function get reflect():Type
		{
			if (_reflect == null) {
				_reflect = Type.reflect(this);
			}
			return _reflect;
		}
		
		private var _store:Store;
		/**
		 * The store that this record belongs to.
		 */
		mesh_internal function get store():Store
		{
			return _store;
		}
		mesh_internal function set store(value:Store):void
		{
			if (_store != null) {
				throw new IllegalOperationError("Cannot reset store on Record.");
			}
			_store = value;
			indexed();
		}
	}
}
