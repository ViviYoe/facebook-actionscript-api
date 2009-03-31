package com.facebook.delegates {
	
	import com.facebook.data.FacebookData;
	import com.facebook.data.FacebookErrorCodes;
	import com.facebook.data.FacebookErrorReason;
	import com.facebook.data.XMLDataParser;
	import com.facebook.errors.FacebookError;
	import com.facebook.events.FacebookEvent;
	import com.facebook.facebook_internal;
	import com.facebook.net.FacebookCall;
	import com.facebook.session.IFacebookSession;
	import com.facebook.session.WebSession;
	
	import flash.events.ErrorEvent;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.HTTPStatusEvent;
	import flash.events.IOErrorEvent;
	import flash.events.SecurityErrorEvent;
	import flash.events.TimerEvent;
	import flash.net.FileReference;
	import flash.net.URLLoader;
	import flash.net.URLLoaderDataFormat;
	import flash.net.URLRequest;
	import flash.net.URLRequestMethod;
	import flash.utils.Timer;
	
	use namespace facebook_internal;
	
	public class WebDelegate extends EventDispatcher implements IFacebookCallDelegate {
		
		protected var parser:XMLDataParser;
		
		protected var connectTimer:Timer;
		protected var loadTimer:Timer;
		
		protected var _call:FacebookCall;
		protected var _session:WebSession;
		
		protected var loader:URLLoader;
		protected var fileRef:FileReference;
		
		public function get call():FacebookCall { return _call; }
		public function set call(newVal:FacebookCall):void { _call = newVal; }

		public function get session():IFacebookSession { return _session; }
		public function set session(newVal:IFacebookSession):void { _session = newVal as WebSession; }
		
		public function WebDelegate(call:FacebookCall, session:WebSession) {
			this.call = call;
			this.session = session;
			
			parser = new XMLDataParser();
			
			connectTimer = new Timer(1000*8, 1);
			connectTimer.addEventListener(TimerEvent.TIMER_COMPLETE, onConnectTimeout);
			
			loadTimer = new Timer(1000*30, 1);
			loadTimer.addEventListener(TimerEvent.TIMER_COMPLETE, onLoadTimeOut);
			
			execute();
		}
		
		public function close():void {
			try {
				loader.close();
			} catch (e:*) { }
			
			connectTimer.stop();
			loadTimer.stop();
		}
		
		protected function onConnectTimeout(p_event:TimerEvent):void {
			var fbError:FacebookError = new FacebookError();
			fbError.errorCode = FacebookErrorCodes.SERVER_ERROR;
			fbError.reason = FacebookErrorReason.CONNECT_TIMEOUT;
			_call.handleError(fbError);
			dispatchEvent(new FacebookEvent(FacebookEvent.COMPLETE, false, false, false, null, fbError));
			
			loadTimer.stop();
			close()
		}
		
		protected function onLoadTimeOut(p_event:TimerEvent):void {
			connectTimer.stop();
			
			close();
			
			var fbError:FacebookError = new FacebookError();
			fbError.errorCode = FacebookErrorCodes.SERVER_ERROR;
			fbError.reason = FacebookErrorReason.LOAD_TIMEOUT;
			_call.handleError(fbError);
			dispatchEvent(new FacebookEvent(FacebookEvent.COMPLETE, false, false, false, null, fbError));
		}

		protected function execute():void {
			if (call == null) { throw new Error('No call defined.'); }
			
			post();
		}

		/**
		 * Helper function for sending the call straight to the server
		 */
		protected function post():void {
			addOptionalArguments();
			
			RequestHelper.formatRequest(call);
			
			//Have a seperate method so sub classes can overrdie this if need be (WebImageUploadDelegate, is an example)
			sendRequest();
			
			connectTimer.start();
		}
		
		protected function sendRequest():void {
			//construct the loader
			createURLLoader();
			
			//create the service request for normal calls
			var req:URLRequest = new URLRequest(_session.rest_url);
			req.contentType = "application/x-www-form-urlencoded";
			req.method = URLRequestMethod.POST;
			
			req.data = call.args;
			
			loader.dataFormat = URLLoaderDataFormat.TEXT;
			loader.load(req);
		}
		
		protected function createURLLoader():void {
			loader = new URLLoader();
			loader.addEventListener(Event.COMPLETE, onDataComplete);
			loader.addEventListener(HTTPStatusEvent.HTTP_STATUS, onHTTPStatus);
			loader.addEventListener(IOErrorEvent.IO_ERROR, onError);
			loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onError);
			loader.addEventListener(Event.OPEN, onOpen);
		}
		
		protected function onHTTPStatus(p_event:HTTPStatusEvent):void { }
		
		protected function onOpen(p_event:Event):void {
			connectTimer.stop();
			loadTimer.start();
		}
		
		/**
		 * Add arguments here that might be class session-type specific
		 */
		protected function addOptionalArguments():void {
			//setting thes 'ss' argument to true
			//since that's what we should be using for a web session
			call.setRequestArgument("ss", true);
		}
		
		// Event Handlers
		protected function onDataComplete(p_event:Event):void {
			handleResult(p_event.target.data as String);
		}
		
		protected function onError(p_event:ErrorEvent):void {
			clean();
			
			var fbError:FacebookError = parser.createFacebookError(p_event, loader.data); 
			
			call.handleError(fbError);
			
			dispatchEvent(new FacebookEvent(FacebookEvent.COMPLETE, false, false, false, null, fbError));
		}
		
		protected function handleResult(result:String):void {
			clean();
			
			var error:FacebookError = parser.validateFacebookResponce(result);
			var fbData:FacebookData;
			
			if (error == null) {
				fbData = parser.parse(result, call.method);
				call.handleResult(fbData);
			} else {
				call.handleError(error);
			}
		}
		
		protected function clean():void {
			connectTimer.stop();
			loadTimer.stop();
			
			if (loader == null) { return; }
			
			loader.removeEventListener(Event.COMPLETE, onDataComplete);
			loader.removeEventListener(IOErrorEvent.IO_ERROR, onError);
			loader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, onError);
			loader.removeEventListener(Event.OPEN, onOpen);
		}
	}
}