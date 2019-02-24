package com.smackwerks.kfb

import io.ktor.application.*
import io.ktor.http.*
import io.ktor.response.*
import io.ktor.routing.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider
import software.amazon.awssdk.auth.credentials.ContainerCredentialsProvider
import software.amazon.awssdk.auth.credentials.EnvironmentVariableCredentialsProvider
import software.amazon.awssdk.auth.credentials.ProfileCredentialsProvider
import software.amazon.awssdk.core.sync.ResponseTransformer
import software.amazon.awssdk.regions.Region

import software.amazon.awssdk.services.s3.S3Client
import software.amazon.awssdk.services.s3.model.GetObjectRequest
import java.io.File

fun awsCredentials(): AwsCredentialsProvider =
    if (File("~/.aws/credentials").exists()) {
        ProfileCredentialsProvider.builder()
            .profileName("ktor-admin")
            .build()
    } else if (System.getenv().containsKey("AWS_ACCESS_KEY_ID")) {
        EnvironmentVariableCredentialsProvider.create()
    } else {
        ContainerCredentialsProvider.builder().build()
    }

fun main() {
    val server = embeddedServer(Netty, 8080) {
        routing {
            get("/") {
                call.respondText("Hello, world!", ContentType.Text.Html)
            }

            get("/s3") {
                val creds = awsCredentials()
                val s3 = S3Client.builder()
                    .region(Region.US_EAST_1)
                    .credentialsProvider(creds)
                    .build()
                val get = GetObjectRequest.builder()
                    .bucket("com.smackwerks-kfb")
                    .key("hello.json")
                    .build()
                val json = s3
                    .getObject(get, ResponseTransformer.toBytes())
                    .asUtf8String()
                call.respondText(json, ContentType.Application.Json)
            }
        }
    }
    server.start(wait = true)
}