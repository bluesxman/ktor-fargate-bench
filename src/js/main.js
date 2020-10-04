'use strict'
var AWS = require("aws-sdk");

AWS.config.update({
    region: "us-east-1"
});

const docClient = new AWS.DynamoDB.DocumentClient();

function query(params) {
  return new Promise((resolve, reject) => {
    docClient.query(params, function(err, data) {
      if (err) {
        reject(err);
      } else {
        resolve(data)
      }
    });
  });
}

function getItem(params) {
  console.log(`docClient keys: ${Object.keys(docClient)}`)
  return new Promise((resolve, reject) => {
    docClient.get(params, function(err, data) {
      if (err) {
        reject(err);
      } else {
        resolve(data)
      }
    });
  });
}

async function getSingleItem() {
  // console.log("Getting 'The Mosquito Coast'");

  var params = {
      TableName : "MoviesPartitionOnly",
      Key: {
        title: 'The Mosquito Coast'
      },
  };

  const data = await getItem(params);
  return data.Item;
}

async function queryYear() {
  // console.log("Querying for movies from 1921.");

  var params = {
      TableName : "Movies",
      KeyConditionExpression: "#yr = :yyyy",
      ExpressionAttributeNames:{
          "#yr": "year"
      },
      ExpressionAttributeValues: {
          ":yyyy": 1921
      }
  };

  const data = await query(params);
  return data.Items;
}

async function queryTitles() {
  // console.log("Querying for movies from 1992 - titles A-L, with genres and lead actor");

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

  const data = await query(params);
  return data.Items;
}

async function bench() {
  const iterations = 20
  let totalTime = 0
  let i

  for (i = 0; i < iterations; i++) {
    const start = Date.now()
    await queryTitles()
    totalTime += Date.now() - start
  }

  return { millis: (totalTime / iterations)}
}

function getRequestId(event, context) {
  return context.awsRequestId
}

async function respondWith(responseFn, requestId) {
  try {
    console.log(`Calling ${responseFn.name}`);
    const obj = await responseFn();
    console.log(`Result: ${obj}`)
    const body = JSON.stringify(obj, null, 2)
    const response = {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json; charset=utf-8'
     },
     body
    }
    return response;
  } catch(err) {
    console.error(err)
    const body = {
      requestId,
      msg: err.message,
    }
    const response = {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json; charset=utf-8'
      },
      body: JSON.stringify(body, null, 2)
    }
    return response;
  }
}

exports.handler = async (event, context, callback) => {
  console.log('Event received')
  return respondWith(queryYear, getRequestId(event, context));
}

// async function main() {
//   const item = await getSingleItem();
//   console.log(item);
// }
//
// main()
