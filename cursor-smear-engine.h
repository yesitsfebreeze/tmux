/* Host bridge to the pinned smear-cursor.nvim engine. */
#ifndef CURSOR_SMEAR_ENGINE_H
#define CURSOR_SMEAR_ENGINE_H
struct smear_engine;
struct smear_input {
    int row, col, width, height, reset, realtime;
    int fg, bg, win, buf, top, line, scroll, origin, winheight;
    char mode;
    double now;
};
struct smear_cell {
    int row, col, fg, bg, blend;
    char text[8];
};
struct smear_engine *smear_engine_new(void);
void smear_engine_free(struct smear_engine *);
int smear_engine_step(struct smear_engine *, const struct smear_input *);
int smear_engine_hidden(struct smear_engine *);
double smear_engine_delay(struct smear_engine *);
unsigned int smear_engine_count(struct smear_engine *);
const struct smear_cell *smear_engine_cell(struct smear_engine *, unsigned int);
const char *smear_engine_error(struct smear_engine *);
#endif
