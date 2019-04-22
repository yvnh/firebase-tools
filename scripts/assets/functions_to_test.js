var functions = require("firebase-functions");
var admin = require("firebase-admin");
admin.initializeApp(functions.config().firebase);

exports.dbAction = functions.database.ref("/input/{uuid}").onWrite(function(change, context) {
  console.log("Received change:", change);
  console.log("Received context:", context);
  return change.after.ref.root.child("output/" + context.params.uuid).set(change.after.val());
});

exports.nested = {
  dbAction: functions.database.ref("/inputNested/{uuid}").onWrite(function(change, context) {
    console.log("Received change:", change);
    console.log("Received context:", context);
    return change.after.ref.root.child("output/" + context.params.uuid).set(change.after.val());
  }),
};

exports.httpsAction = functions.https.onRequest(function(req, res) {
  res.send(req.body);
});

exports.pubsubAction = functions.pubsub.topic("topic1").onPublish(function(message) {
  console.log("Received message:", message);
  var message = Buffer.from(message.data, "base64").toString();
  message = JSON.parse(message);
  return admin
    .database()
    .ref("output/" + message.uuid)
    .set(message.uuid);
});

exports.gcsAction = functions.storage.object().onFinalize(function(obj) {
  console.log("Received object:", obj);
  var uuid = obj.name;
  return admin
    .database()
    .ref("output/" + uuid)
    .set(uuid);
});

exports.pubsubScheduleAction = functions.pubsub.schedule("every 10 minutes").onRun(function(event) {
  console.log("Received scheduled event:", event);
  return true;
});
