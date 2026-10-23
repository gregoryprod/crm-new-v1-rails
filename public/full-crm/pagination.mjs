export function pageWindow(total,requested,size=40){
  const pages=Math.max(1,Math.ceil(total/size));
  const page=Math.max(1,Math.min(pages,Number.isSafeInteger(requested)?requested:1));
  return {page,pages,start:(page-1)*size,end:Math.min(page*size,total)};
}
