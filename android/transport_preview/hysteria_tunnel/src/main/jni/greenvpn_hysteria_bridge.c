#define _GNU_SOURCE

#include <jni.h>

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

static pthread_mutex_t fd_control_mutex = PTHREAD_MUTEX_INITIALIZER;
static int fd_control_server = -1;
static int fd_control_stop = 0;
static char fd_control_path[sizeof(((struct sockaddr_un *)0)->sun_path)];

static int copy_jstring(JNIEnv *env, jstring value, char *target, size_t size)
{
    const char *text;
    size_t length;

    if (value == NULL || size == 0) {
        return -1;
    }
    text = (*env)->GetStringUTFChars(env, value, NULL);
    if (text == NULL) {
        return -1;
    }
    length = strlen(text);
    if (length == 0 || length >= size) {
        (*env)->ReleaseStringUTFChars(env, value, text);
        return -1;
    }
    memcpy(target, text, length + 1);
    (*env)->ReleaseStringUTFChars(env, value, text);
    return 0;
}

static int receive_one_fd(int socket_fd)
{
    char payload = 0;
    char control[CMSG_SPACE(sizeof(int))];
    struct iovec iov = { .iov_base = &payload, .iov_len = sizeof(payload) };
    struct msghdr message;
    struct cmsghdr *header;
    int received_fd = -1;

    memset(&message, 0, sizeof(message));
    memset(control, 0, sizeof(control));
    message.msg_iov = &iov;
    message.msg_iovlen = 1;
    message.msg_control = control;
    message.msg_controllen = sizeof(control);
    if (recvmsg(socket_fd, &message, 0) <= 0) {
        return -1;
    }
    for (header = CMSG_FIRSTHDR(&message); header != NULL;
         header = CMSG_NXTHDR(&message, header)) {
        if (header->cmsg_level == SOL_SOCKET && header->cmsg_type == SCM_RIGHTS &&
            header->cmsg_len >= CMSG_LEN(sizeof(int))) {
            memcpy(&received_fd, CMSG_DATA(header), sizeof(received_fd));
            break;
        }
    }
    if (received_fd >= 0) {
        (void)fcntl(received_fd, F_SETFD, FD_CLOEXEC);
    }
    return received_fd;
}

JNIEXPORT jint JNICALL
Java_pro_greenvpn_hysteria_Hysteria2VpnService_nativeRunFdControl(
    JNIEnv *env, jobject service, jstring socket_path)
{
    struct sockaddr_un address;
    jclass service_class;
    jmethodID protect_method;
    char path[sizeof(address.sun_path)];
    int server_fd = -1;
    int result = -1;

    if (copy_jstring(env, socket_path, path, sizeof(path)) != 0) {
        return -1;
    }
    service_class = (*env)->GetObjectClass(env, service);
    protect_method = (*env)->GetMethodID(env, service_class, "protectSocket", "(I)Z");
    if (protect_method == NULL) {
        return -2;
    }

    server_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (server_fd < 0) {
        return -3;
    }
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    memcpy(address.sun_path, path, strlen(path) + 1);
    unlink(path);

    mode_t old_mask = umask(0077);
    int bind_result = bind(server_fd, (struct sockaddr *)&address,
                           offsetof(struct sockaddr_un, sun_path) + strlen(path) + 1);
    umask(old_mask);
    if (bind_result != 0 || chmod(path, 0600) != 0 || listen(server_fd, 8) != 0) {
        goto cleanup;
    }

    pthread_mutex_lock(&fd_control_mutex);
    fd_control_server = server_fd;
    fd_control_stop = 0;
    memcpy(fd_control_path, path, strlen(path) + 1);
    pthread_mutex_unlock(&fd_control_mutex);
    result = 0;

    for (;;) {
        int client_fd;
        int received_fd;
        uint8_t response = 0;
        int should_stop;

        pthread_mutex_lock(&fd_control_mutex);
        should_stop = fd_control_stop;
        pthread_mutex_unlock(&fd_control_mutex);
        if (should_stop) {
            break;
        }
        client_fd = accept4(server_fd, NULL, NULL, SOCK_CLOEXEC);
        if (client_fd < 0) {
            if (errno == EINTR) {
                continue;
            }
            pthread_mutex_lock(&fd_control_mutex);
            should_stop = fd_control_stop;
            pthread_mutex_unlock(&fd_control_mutex);
            if (!should_stop) {
                result = -4;
            }
            break;
        }
        received_fd = receive_one_fd(client_fd);
        if (received_fd >= 0) {
            jboolean protected_ok = (*env)->CallBooleanMethod(
                env, service, protect_method, (jint)received_fd);
            if (!(*env)->ExceptionCheck(env) && protected_ok == JNI_TRUE) {
                response = 1;
            } else if ((*env)->ExceptionCheck(env)) {
                (*env)->ExceptionClear(env);
            }
            close(received_fd);
        }
        (void)send(client_fd, &response, sizeof(response), MSG_NOSIGNAL);
        close(client_fd);
    }

cleanup:
    pthread_mutex_lock(&fd_control_mutex);
    if (fd_control_server == server_fd) {
        fd_control_server = -1;
        close(server_fd);
    }
    fd_control_path[0] = '\0';
    pthread_mutex_unlock(&fd_control_mutex);
    unlink(path);
    return result;
}

JNIEXPORT void JNICALL
Java_pro_greenvpn_hysteria_Hysteria2VpnService_nativeStopFdControl(
    JNIEnv *env, jobject service)
{
    int server_fd;
    char path[sizeof(fd_control_path)];
    (void)env;
    (void)service;

    pthread_mutex_lock(&fd_control_mutex);
    fd_control_stop = 1;
    server_fd = fd_control_server;
    fd_control_server = -1;
    memcpy(path, fd_control_path, sizeof(path));
    pthread_mutex_unlock(&fd_control_mutex);
    if (server_fd >= 0) {
        shutdown(server_fd, SHUT_RDWR);
        close(server_fd);
    }
    if (path[0] != '\0') {
        unlink(path);
    }
}
