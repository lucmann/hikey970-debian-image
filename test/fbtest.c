#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <linux/fb.h>
#include <string.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    int fb_fd;
    struct fb_var_screeninfo vinfo;
    struct fb_fix_screeninfo finfo;
    long screensize;
    uint8_t *fbp;
    
    // 打开 framebuffer 设备
    fb_fd = open("/dev/fb0", O_RDWR);
    if (fb_fd == -1) {
        perror("无法打开 /dev/fb0");
        return 1;
    }
    
    // 获取固定屏幕信息
    if (ioctl(fb_fd, FBIOGET_FSCREENINFO, &finfo) == -1) {
        perror("获取固定屏幕信息失败");
        close(fb_fd);
        return 1;
    }
    
    // 获取可变屏幕信息
    if (ioctl(fb_fd, FBIOGET_VSCREENINFO, &vinfo) == -1) {
        perror("获取可变屏幕信息失败");
        close(fb_fd);
        return 1;
    }
    
    printf("resolution:   %dx%d\n", vinfo.xres, vinfo.yres);
    printf("depth:        %d bpp\n", vinfo.bits_per_pixel);
    printf("yres_virtual: %d lines\n", vinfo.yres_virtual);
    printf("line_length:  %d bytes\n", finfo.line_length);
    
    // 计算屏幕大小
    screensize = vinfo.yres_virtual * finfo.line_length;
    
    // 将 framebuffer 映射到内存
    fbp = (uint8_t *)mmap(0, screensize, PROT_READ | PROT_WRITE, MAP_SHARED, fb_fd, 0);
    if (fbp == MAP_FAILED) {
        perror("mmap 失败");
        close(fb_fd);
        return 1;
    }
    
    printf("开始刷屏...\n");
    printf("按 Ctrl+C 退出\n\n");
    
    // 定义几种颜色 (BGRA 格式)
    uint32_t colors[] = {
        0xFFFF0000,  // 红色
        0xFF00FF00,  // 绿色
        0xFF0000FF,  // 蓝色
        0xFFFFFF00,  // 黄色
        0xFFFF00FF,  // 品红
        0xFF00FFFF,  // 青色
        0xFFFFFFFF,  // 白色
        0xFF000000,  // 黑色
    };
    int num_colors = sizeof(colors) / sizeof(colors[0]);
    const char *color_names[] = {"红色", "绿色", "蓝色", "黄色", "品红", "青色", "白色", "黑色"};
    
    int color_idx = 0;
    
    // 刷屏循环
    while (1) {
        uint32_t color = colors[color_idx];
        uint8_t r = (color >> 16) & 0xFF;
        uint8_t g = (color >> 8) & 0xFF;
        uint8_t b = color & 0xFF;
        
        printf("\r当前颜色: %-6s (R:%3d G:%3d B:%3d)", 
               color_names[color_idx], r, g, b);
        fflush(stdout);
        
        // 填充整个屏幕
        for (uint32_t y = 0; y < vinfo.yres; y++) {
            for (uint32_t x = 0; x < vinfo.xres; x++) {
                long location = (x + vinfo.xoffset) * (vinfo.bits_per_pixel / 8) +
                               (y + vinfo.yoffset) * finfo.line_length;
                
                if (vinfo.bits_per_pixel == 32) {
                    // 32位色: 考虑各通道偏移
                    *(fbp + location + (vinfo.red.offset / 8))   = r;
                    *(fbp + location + (vinfo.green.offset / 8)) = g;
                    *(fbp + location + (vinfo.blue.offset / 8))  = b;
                    *(fbp + location + 3) = 0xFF;  // Alpha
                } else if (vinfo.bits_per_pixel == 16) {
                    // 16位色 (RGB565)
                    uint16_t pixel = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
                    *((uint16_t *)(fbp + location)) = pixel;
                } else if (vinfo.bits_per_pixel == 24) {
                    // 24位色
                    *(fbp + location + (vinfo.red.offset / 8))   = r;
                    *(fbp + location + (vinfo.green.offset / 8)) = g;
                    *(fbp + location + (vinfo.blue.offset / 8))  = b;
                }
            }
        }
        
        color_idx = (color_idx + 1) % num_colors;
        sleep(1);  // 每秒切换一次颜色
    }
    
    // 清理 (实际上因为无限循环不会到达这里)
    munmap(fbp, screensize);
    close(fb_fd);
    
    return 0;
}

