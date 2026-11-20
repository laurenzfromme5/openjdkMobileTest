#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "jni.h"

extern void loadfunctions(void);

static void fail(const char *why) {
    fprintf(stderr, "[probe] FEHLER: %s\n", why);
    fflush(stderr);
    exit(1);
}

int main(int argc, char *argv[]) {
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
    NSString *jar = [resourcePath stringByAppendingPathComponent:@"HelloWorld.jar"];
    NSString *classPathOption = [NSString stringWithFormat:@"-Djava.class.path=%@", jar];

    fprintf(stderr, "[probe] bundle=%s\n", [resourcePath UTF8String]);
    fprintf(stderr, "[probe] %s\n", [classPathOption UTF8String]);

    JavaVMOption options[1];
    options[0].optionString = strdup([classPathOption UTF8String]);

    JavaVMInitArgs vm_args;
    vm_args.version = JNI_VERSION_1_8;
    vm_args.nOptions = 1;
    vm_args.options = options;
    vm_args.ignoreUnrecognized = JNI_FALSE;

    fprintf(stderr, "[probe] loadfunctions\n");
    loadfunctions();

    fprintf(stderr, "[probe] JNI_CreateJavaVM\n");
    JavaVM *jvm;
    JNIEnv *env;
    if (JNI_CreateJavaVM(&jvm, (void **)&env, &vm_args) != JNI_OK) {
        fail("JNI_CreateJavaVM");
    }
    fprintf(stderr, "[probe] VM erzeugt\n");

    jclass cls = (*env)->FindClass(env, "HelloWorld");
    if (cls == NULL) {
        fail("FindClass HelloWorld");
    }
    jmethodID mid = (*env)->GetStaticMethodID(env, cls, "main", "([Ljava/lang/String;)V");
    if (mid == NULL) {
        fail("GetStaticMethodID main");
    }

    jclass strCls = (*env)->FindClass(env, "java/lang/String");
    if (strCls == NULL) {
        fail("FindClass java/lang/String");
    }
    jobjectArray emptyArgs = (*env)->NewObjectArray(env, 0, strCls, NULL);
    if (emptyArgs == NULL) {
        fail("NewObjectArray");
    }

    fprintf(stderr, "[probe] HelloWorld.main aufrufen\n");
    (*env)->CallStaticVoidMethod(env, cls, mid, emptyArgs);
    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionDescribe(env);
        fail("Exception in HelloWorld.main");
    }

    fflush(stdout);
    fflush(stderr);
    (*jvm)->DestroyJavaVM(jvm);
    fprintf(stderr, "[probe] VM beendet\n");
    return 0;
}
