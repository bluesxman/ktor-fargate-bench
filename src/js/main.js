'use strict'
var AWS = require("aws-sdk");

AWS.config.update({
    region: "us-east-1"
});

var docClient = new AWS.DynamoDB.DocumentClient();

function queryTitles(callback) {
  var docClient = new AWS.DynamoDB.DocumentClient();

  console.log("Querying for movies from 1992 - titles A-L, with genres and lead actor");
  
  var params = {
      TableName : "Movies",
      ProjectionExpression:"#yr, title, info.genres, info.actors[0]",
      KeyConditionExpression: "#yr = :yyyy and title between :letter1 and :letter2",
      ExpressionAttributeNames:{
          "#yr": "year"
      },
      ExpressionAttributeValues: {
          ":yyyy": 1992,
          ":letter1": "A",
          ":letter2": "L"
      }
  };
  
  docClient.query(params, function(err, data) {
      if (err) {
          console.log("Unable to query. Error:", JSON.stringify(err, null, 2));
          callback({
            statusCode: 500,
            headers: {
              'Content-Type': 'application/json; charset=utf-8'
            },
            body: err
          });
      } else {
          console.log("Query succeeded.");
          const response = {
            statusCode: 200,
            headers: {
              'Content-Type': 'application/json; charset=utf-8'
            },
            body: JSON.stringify(data.Items, null, 2)
          }
          // const response = {
          //       statusCode: 200,
          //       headers: {
          //         'Content-Type': 'text/html; charset=utf-8'
          //       },
          //       body: `<p>${JSON.stringify(data.Items, null, 2)}</p>`
          //     }
          callback(null, response);
      }
  });  
}

function benchDynamo(calls) {

}

exports.handler = function(event, context, callback) {
  console.log ('entered handler')

  queryTitles(callback)
}


// exports.handler = function(event, context, callback) {
//   console.log ('entered handler')

//   var response = {
//     statusCode: 200,
//     headers: {
//       'Content-Type': 'text/html; charset=utf-8'
//     },
//     body: '<p>Hello meh!</p>'
//   }
//   callback(null, response)
// }