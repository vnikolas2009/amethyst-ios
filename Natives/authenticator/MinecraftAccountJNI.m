#include "jni.h"

// Called from Java (MinecraftAccount.parse) only when an account file has an "xuid",
// i.e. an old Microsoft account. Online accounts no longer exist and no tokens are
// stored anywhere, so always return the same placeholder the Java side uses for
// offline accounts. The function must stay: Java declares it as a native method.
JNIEXPORT jstring JNICALL Java_net_kdt_pojavlaunch_value_MinecraftAccount_getAccessTokenFromKeychain(JNIEnv *env, jclass clazz, jstring xuid) {
    return (*env)->NewStringUTF(env, "0");
}
