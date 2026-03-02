#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <libdrm/drm.h>
#include <libdrm/drm_mode.h>

int main() {
    int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
    if (fd < 0) { perror("open"); return 1; }

    if (ioctl(fd, DRM_IOCTL_SET_MASTER, 0))
      perror("set_master");

    /* 1. 先获取数量 */
    struct drm_mode_card_res res = {};
    ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res);
    printf("connectors=%d crtcs=%d fbs=%d encoders=%d\n",
           res.count_connectors, res.count_crtcs,
           res.count_fbs, res.count_encoders);

    /* 2. 分配空间再获取 id 列表 */
    uint32_t *conn_ids = calloc(res.count_connectors, sizeof(uint32_t));
    uint32_t *crtc_ids = calloc(res.count_crtcs, sizeof(uint32_t));
    res.connector_id_ptr = (uint64_t)(uintptr_t)conn_ids;
    res.crtc_id_ptr      = (uint64_t)(uintptr_t)crtc_ids;
    if(ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res))
      perror("MODE_GETRESOURCES");

    for (int i = 0; i < res.count_connectors; i++)
        printf("  connector[%d] id=%d\n", i, conn_ids[i]);
    for (int i = 0; i < res.count_crtcs; i++)
        printf("  crtc[%d] id=%d\n", i, crtc_ids[i]);

    /* 3. 找 connected 的 connector */
    int conn_idx = -1;
    struct drm_mode_get_connector conn = {};
    struct drm_mode_modeinfo *modes = NULL;

    for (int i = 0; i < res.count_connectors; i++) {
        memset(&conn, 0, sizeof(conn));
        //conn.connector_id = conn_ids[i];
        conn.connector_id = 37;
        ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &conn);
        printf("connector id=%d status=%d modes=%d type=%d\n",
               conn_ids[i], conn.connection, conn.count_modes, conn.connector_type);

        int count_modes = conn.count_modes;

        if (conn.connection == 1 && conn.count_modes > 0) {
            /* 分配 modes 空间再读 */
            modes = calloc(conn.count_modes, sizeof(*modes));
            conn.modes_ptr = (uint64_t)(uintptr_t)modes;
            conn.count_modes = count_modes;
            ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &conn);
            conn_idx = i;
            break;
        }
    }

    if (conn_idx < 0) { printf("no connected connector with modes!\n"); return 1; }

    struct drm_mode_modeinfo *mode = &modes[0];
    printf("using mode: %dx%d name=%s\n", mode->hdisplay, mode->vdisplay, mode->name);

    /* 4. 创建 dumb buffer */
    struct drm_mode_create_dumb create = {};
    create.width  = mode->hdisplay;
    create.height = mode->vdisplay;
    create.bpp    = 32;
    if (ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &create)) {
        perror("create dumb"); return 1;
    }
    printf("dumb handle=%d pitch=%d size=%llu\n",
           create.handle, create.pitch, create.size);

    /* 5. add fb */
    struct drm_mode_fb_cmd fb = {};
    fb.width  = mode->hdisplay;
    fb.height = mode->vdisplay;
    fb.pitch  = create.pitch;
    fb.bpp    = 32;
    fb.depth  = 24;
    fb.handle = create.handle;
    if (ioctl(fd, DRM_IOCTL_MODE_ADDFB, &fb)) { perror("addfb"); return 1; }
    printf("fb_id=%d\n", fb.fb_id);

    /* 6. mmap */
    struct drm_mode_map_dumb map = {};
    map.handle = create.handle;
    ioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &map);
    uint32_t *pixels = mmap(0, create.size, PROT_READ|PROT_WRITE,
                            MAP_SHARED, fd, map.offset);
    if (pixels == MAP_FAILED) { perror("mmap"); return 1; }

    /* 7. 填红色 */
    for (uint32_t i = 0; i < create.size/4; i++)
        pixels[i] = 0x00FF0000;
    printf("filled RED\n");

    /* 8. set crtc */
    struct drm_mode_crtc crtc = {};
    crtc.crtc_id            = crtc_ids[0];
    crtc.fb_id              = fb.fb_id;
    crtc.set_connectors_ptr = (uint64_t)(uintptr_t)&conn_ids[conn_idx];
    crtc.count_connectors   = 1;
    crtc.mode               = *mode;
    crtc.mode_valid         = 1;
    if (ioctl(fd, DRM_IOCTL_MODE_SETCRTC, &crtc)) {
        perror("setcrtc"); return 1;
    }
    printf("SUCCESS! screen should be RED\n");
    sleep(5);

    for (uint32_t i = 0; i < create.size/4; i++)
        pixels[i] = 0x000000FF;
    printf("now BLUE\n");
    sleep(5);

    return 0;
}

