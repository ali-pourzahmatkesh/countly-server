'use strict';

var _               = require('underscore'),
    common 			= require('../../../../api/utils/common.js'),
    log             = common.log('push:scheduler'),
	pushly 			= require('./lib')(),
    mess            = require('./message.js'),
    cluster			= require('cluster'),
    Message         = mess.Message,
    MessageStatus   = mess.MessageStatus;

var check = function() {
    function addPushly(appId, match, creds, query, message, pushly) {
        log.d('Adding pushly message for %j with creds %j & query %j & match %j', message, creds, query, match);
        common.db.collection('app_users' + appId).count(match, function(err, count){
            if (count) {
                var updateQuery = _.extend({}, query);
                if (typeof updateQuery.conditions === 'object') {
                    updateQuery.conditions = JSON.stringify(updateQuery.conditions);
                }
                var msg = message.toPushly(creds, query, [''+ appId, creds.id]),
                    upd = {
                        $addToSet: {pushly: {id: msg.id, query: updateQuery, result: msg.result}},
                        $set: {'result.status': MessageStatus.InQueue}
                    };

                log.d('Adding pushly to %j (%d): %j', {_id: message._id}, count, upd);
                common.db.collection('messages').update(
                    {_id: message._id},
                    upd, 
                    function(){
                        pushly.push(msg);
                    }
                );
            } else {
                log.d('Won\'t add pushly message for %j with creds %j & query %j: %j / %j', message, creds, query, err, count);
            }
        });
    }

	common.db.collection('messages').findAndModify(
		{date: {$lt: new Date()}, 'result.status': MessageStatus.Initial, 'deleted': {$exists: false}},
		[['date', 1]],
		{$set: {'result.status': MessageStatus.InProcessing}},
		{'new': true},

		function(err, message){
            message = message ? message.value : null;
			if (message) {
                log.d('Processing message %j', message);

				message = new Message(message);
				var conditions = message.getUserCollectionConditions();

                // pushly submessages
				message.pushly = [];

				common.db.collection('apps').find({_id: {$in: message.apps}}).toArray(function(err, apps){
					if (apps) for (var m = message.apps.length - 1; m >= 0; m--) {
						var appId = message.apps[m],
							app;

						for (var k in apps) if (apps[k]._id.toString() === appId.toString()) app = apps[k];

						if (app) {
                            // query used to get device tokens when message gets to the top of queue
							var query = {appId: appId, conditions: conditions},
								credentials = require('./endpoints.js').credentials(message, app);

                            log.d('Credentials for message %j', credentials);

                            if (credentials.length === 0) {
                                // no device credentials is provided for all app-platform-(test or not) combinations
                                common.db.collection('messages').update({_id: message._id}, {$set: {
                                    result: {
                                        status: MessageStatus.Aborted | MessageStatus.Error,
                                        error: 'No credentials provided'
                                    }}},function(){});
                            } else {
                                for (var c = credentials.length - 1; c >= 0; c--) {
                                    var creds = credentials[c];

                                    var field = creds.id.split('.')[0],
                                        match = _.extend({}, conditions);
                                    match[common.dbUserMap.tokens + field] = true;

                                    // count first to prevent no users errors within some of app-platform combinations
                                    // of the message which will turn message status to error
                                    addPushly(app._id, match, creds, query, message, pushly);
                                }
                            }
						} else {
                            log.e('!!!!!!!!!!!!! App not found in findAndModify !!!');
                        }
					}

                    // if (message.pushly.length) {
                        // common.db.collection('messages').update({_id: message._id}, {$set: {pushly: message.pushly, 'result.status': MessageStatus.InQueue}},function(){});
                        // toPush.forEach(pushly.push.bind(pushly));
                    // }
				});
            }
		}
	);
};

var launched = false;

var periodicCheck = function(){
    if (cluster.isMaster) {
        if (!launched) {
            setTimeout(function(){  // wait for app to start
                common.db.collection('messages').update({'result.status': {$in: [MessageStatus.Initial, MessageStatus.InProcessing, MessageStatus.InProcessing | MessageStatus.Done, MessageStatus.InQueue, MessageStatus.InQueue | MessageStatus.InProcessing]}}, {$set: {'result.status': MessageStatus.Done | MessageStatus.Aborted | MessageStatus.Error, 'result.error': 'Server was restarted when sending message'}}, {multi: true}, function(){
                    launched = true;
                    check();
                    setTimeout(periodicCheck, 3000);
                });
            }, 5000);
        } else {
            check();
            setTimeout(periodicCheck, 3000);
        }
    }
};

module.exports = periodicCheck;
