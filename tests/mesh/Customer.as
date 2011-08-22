package mesh
{
	import mesh.core.object.copy;
	import mesh.model.validators.PresenceValidator;
	
	import mx.collections.IList;
	
	public class Customer extends Person
	{
		public static var validate:Object = 
		{
			address: [{validator:PresenceValidator}]
		};
		
		[Bindable] public var address:Address;
		[Bindable] public var accountId:int;
		[Bindable] public var account:Account;
		[Bindable] public var orders:IList;
		
		public function Customer(properties:Object = null)
		{
			super(properties);
			
			hasOne("account", {inverse:"customer"});
			hasMany("orders", {inverse:"customer"});
		}
		
		override public function toObject():Object
		{
			var result:Object = super.toObject();
			copy(this, result, {includes:["address", "accountId"]});
			return result;
		}
	}
}