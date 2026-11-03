using Khách_Sạn_5_sao.Models;
using System;
using System.Linq;
using System.Collections.Generic;
using System.Web;
using System.Web.Mvc;

namespace Khách_Sạn_5_sao.Controllers
{
    public class RoomDetailsController : Controller
    {
        private readonly booking_dbEntities database =
            new booking_dbEntities();

        public class DetailRow
        {
            public string Name { get; set; }
            public string TypeName { get; set; }
            public string Area { get; set; }
            public string Bed { get; set; }
            public string ViewName { get; set; }
            public int Capacity { get; set; }

            public string Description { get; set; }
            public string Highlights { get; set; }
            public string Common { get; set; }
            public string Space { get; set; }
            public string Bathroom { get; set; }
            public string Equipment { get; set; }
            public string Amenities { get; set; }
            public string IdealFor { get; set; }
            public string Notes { get; set; }

            public bool IsDemo { get; set; }
        }

        private string[] Items(
            string value,
            HashSet<string> seen)
        {
            return (value ?? "")
                .Split(
                    new[] { '|' },
                    StringSplitOptions.RemoveEmptyEntries)
                .Select(x => x.Trim())
                .Where(x => x.Length > 0 && seen.Add(x))
                .ToArray();
        }

        [HttpGet]
        public JsonResult Get(string room_id)
        {
            Response.Cache.SetCacheability(
                HttpCacheability.NoCache);

            Response.Cache.SetNoStore();

            if (string.IsNullOrWhiteSpace(room_id)
                || room_id.Length > 50)
            {
                Response.StatusCode = 400;

                return Json(
                    new
                    {
                        success = false,
                        message = "Vui lòng chọn phòng."
                    },
                    JsonRequestBehavior.AllowGet);
            }

            var row = database.Database.SqlQuery<DetailRow>(
                @"
                SELECT
                    COALESCE(
                        NULLIF(LTRIM(RTRIM(r.ten_phong)), N''),
                        N'Phòng nghỉ'
                    ) AS Name,

                    t.ten_loai AS TypeName,
                    t.dien_tich AS Area,
                    t.giuong AS Bed,
                    t.view_phong AS ViewName,
                    ISNULL(t.suc_chua, 2) AS Capacity,

                    COALESCE(
                        p.mo_ta,
                        N'Khách sạn đang cập nhật mô tả chi tiết cho phòng này.'
                    ) AS Description,

                    p.diem_noi_bat AS Highlights,
                    p.tien_nghi_chung AS Common,
                    p.khong_gian AS Space,
                    p.phong_tam AS Bathroom,
                    p.thiet_bi AS Equipment,

                    COALESCE(
                        p.tien_ich,
                        t.tien_nghi
                    ) AS Amenities,

                    p.phu_hop AS IdealFor,

                    COALESCE(
                        p.luu_y,
                        N'Vui lòng liên hệ khách sạn để xác nhận tiện nghi.'
                    ) AS Notes,

                    CAST(
                        ISNULL(p.la_noi_dung_mau, 1)
                        AS bit
                    ) AS IsDemo

                FROM dbo.Rooms r

                JOIN dbo.Room_Types t
                    ON t.type_id = r.type_id

                LEFT JOIN dbo.Room_Profiles p
                    ON p.room_id = r.room_id

                WHERE r.room_id = @p0
                ",
                room_id
            ).SingleOrDefault();

            if (row == null)
            {
                Response.StatusCode = 404;

                return Json(
                    new
                    {
                        success = false,
                        message = "Không tìm thấy phòng."
                    },
                    JsonRequestBehavior.AllowGet);
            }

            var seen = new HashSet<string>(
                StringComparer.CurrentCultureIgnoreCase);

            return Json(
                new
                {
                    success = true,
                    name = row.Name,
                    typeName = row.TypeName,
                    area = row.Area,
                    bed = row.Bed,
                    view = row.ViewName,
                    capacity = row.Capacity,
                    description = row.Description,
                    isDemo = row.IsDemo,

                    sections = new[]
                    {
                        new
                        {
                            title = "Điểm nổi bật riêng",
                            items = Items(row.Highlights, seen)
                        },
                        new
                        {
                            title = "Không gian trong phòng",
                            items = Items(row.Space, seen)
                        },
                        new
                        {
                            title = "Phòng tắm",
                            items = Items(row.Bathroom, seen)
                        },
                        new
                        {
                            title = "Trang bị bổ sung",
                            items = Items(row.Equipment, seen)
                        },
                        new
                        {
                            title = "Tiện ích và dịch vụ",
                            items = Items(row.Amenities, seen)
                        },
                        new
                        {
                            title = "Tiện nghi cơ bản dùng chung",
                            items = Items(row.Common, seen)
                        },
                        new
                        {
                            title = "Phù hợp với",
                            items = Items(row.IdealFor, seen)
                        },
                        new
                        {
                            title = "Thông tin cần biết",
                            items = Items(row.Notes, seen)
                        }
                    }
                },
                JsonRequestBehavior.AllowGet);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                database.Dispose();
            }

            base.Dispose(disposing);
        }
    }
}