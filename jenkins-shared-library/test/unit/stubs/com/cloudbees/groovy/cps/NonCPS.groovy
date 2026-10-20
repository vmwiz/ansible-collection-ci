package com.cloudbees.groovy.cps
// Stub pour compiler Config hors Jenkins (la vraie annotation vient du plugin workflow-cps).
import java.lang.annotation.*
@Retention(RetentionPolicy.RUNTIME)
@Target([ElementType.METHOD, ElementType.CONSTRUCTOR])
@interface NonCPS {}
