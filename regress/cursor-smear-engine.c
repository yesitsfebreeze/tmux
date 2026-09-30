#include <stdio.h>
#include <string.h>
#include "cursor-smear-engine.h"
int main(void)
{
    struct smear_engine *engine=smear_engine_new();
    struct smear_input in;
    const struct smear_cell *cell;
    unsigned int i;
    if (!engine) return 1;
    memset(&in,0,sizeof in);
    while (scanf("%lf %d %d %c %d %d %d %d %d %d %d %d %d %d %d %d",
        &in.now,&in.row,&in.col,&in.mode,&in.reset,&in.width,&in.height,
        &in.fg,&in.bg,&in.win,&in.buf,&in.top,&in.line,&in.scroll,&in.origin,&in.winheight)==16) {
        if (smear_engine_step(engine,&in)) {
            fprintf(stderr,"%s\n",smear_engine_error(engine)); return 1;
        }
        printf("F %d %.6f %u\n",smear_engine_hidden(engine),
            smear_engine_delay(engine),smear_engine_count(engine));
        for (i=0;i<smear_engine_count(engine);i++) {
            cell=smear_engine_cell(engine,i);
            printf("C %d %d %s %d %d %d\n",cell->row,cell->col,
                cell->text,cell->fg,cell->bg,cell->blend);
        }
    }
    smear_engine_free(engine);
    return 0;
}
