using Khách_Sạn_5_sao.Models;
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Mvc;

namespace Khách_Sạn_5_sao.Controllers
{
    public class DiningController : Controller
    {
        private readonly booking_dbEntities database =
            new booking_dbEntities();

        public class ServiceRow
        {
            public int Id { get; set; }
            public string Code { get; set; }
            public string GroupCode { get; set; }
            public string Name { get; set; }
            public string Description { get; set; }
            public string PricingMode { get; set; }
            public decimal? UnitPrice { get; set; }
            public string ImageUrl { get; set; }
            public bool PayOnline { get; set; }
        }

        public class SlotRow
        {
            public int Id { get; set; }
            public int ServiceId { get; set; }
            public string Time { get; set; }
            public string ServiceName { get; set; }
        }

        public class ReservationRow
        {
            public string Code { get; set; }
            public string GroupCode { get; set; }
            public string ServiceName { get; set; }
            public DateTime VisitAt { get; set; }
            public int Guests { get; set; }
            public string PricingMode { get; set; }
            public decimal? UnitPrice { get; set; }
            public decimal? EstimatedTotal { get; set; }
            public string FullName { get; set; }
            public string Phone { get; set; }
            public string Email { get; set; }
            public string Notes { get; set; }
            public string Status { get; set; }
            public string StaffNote { get; set; }
            public string CancellationReason { get; set; }
            public DateTime CreatedAtUtc { get; set; }
        }

        public class BookingPage
        {
            public string GroupCode { get; set; }

            public string GroupTitle
            {
                get
                {
                    return GroupCode == "WELLNESS"
                        ? "Thư giãn & Sức khỏe"
                        : "Nhà hàng & Ẩm thực";
                }
            }

            [Required(ErrorMessage = "Vui lòng chọn dịch vụ.")]
            public int? ServiceId { get; set; }

            [Required(ErrorMessage = "Vui lòng chọn khung giờ.")]
            public int? SlotId { get; set; }

            [Required(ErrorMessage = "Vui lòng chọn ngày đến.")]
            public DateTime? VisitDate { get; set; }

            [Required(ErrorMessage = "Vui lòng nhập số người.")]
            [Range(1, 20, ErrorMessage = "Số người từ 1 đến 20.")]
            public int? Guests { get; set; }

            [Required(ErrorMessage = "Vui lòng nhập họ tên.")]
            [StringLength(150, MinimumLength = 2,
                ErrorMessage = "Họ tên từ 2 đến 150 ký tự.")]
            public string FullName { get; set; }

            [Required(ErrorMessage = "Vui lòng nhập số điện thoại.")]
            [StringLength(32)]
            public string Phone { get; set; }

            [EmailAddress(ErrorMessage = "Email không hợp lệ.")]
            [StringLength(255)]
            public string Email { get; set; }

            [StringLength(1000,
                ErrorMessage = "Ghi chú tối đa 1000 ký tự.")]
            public string Notes { get; set; }

            public bool Agree { get; set; }
            public int PaymentPercent { get; set; } = 30;

            [Required]
            [StringLength(32)]
            public string RequestToken { get; set; }

            public DateTime Today { get; set; }
            public List<ServiceRow> Services { get; set; }
            public List<SlotRow> Slots { get; set; }
        }

        public class LookupPage
        {
            [Required(ErrorMessage = "Vui lòng nhập mã đặt dịch vụ.")]
            [StringLength(24)]
            public string Code { get; set; }

            [Required(ErrorMessage = "Vui lòng nhập số điện thoại.")]
            [StringLength(32)]
            public string Phone { get; set; }

            public ReservationRow Order { get; set; }
            public bool CanCancel { get; set; }
            public bool AskCancel { get; set; }
        }

        private const string ServiceSelect = @"
            SELECT service_id AS Id,service_code AS Code,
                service_group AS GroupCode,service_name AS Name,
                description AS Description,pricing_mode AS PricingMode,
                unit_price AS UnitPrice,image_url AS ImageUrl,
                CONVERT(BIT,CASE
                    WHEN pricing_mode='PER_PERSON' AND unit_price>0
                    AND EXISTS(
                        SELECT 1 FROM dbo.Dining_ServiceInventory i
                        WHERE i.service_id=Dining_Services.service_id
                          AND i.enabled=1
                    )
                    THEN 1 ELSE 0 END) AS PayOnline
            FROM dbo.Dining_Services ";

        private static DateTime HotelNow()
        {
            return DateTime.UtcNow.AddHours(7);
        }

        private static string NormalizeGroup(string value)
        {
            string group = (value ?? "DINING").Trim().ToUpperInvariant();
            return group == "DINING" || group == "WELLNESS"
                ? group : null;
        }

        private static string NormalizePhone(string value)
        {
            string phone = Regex.Replace(
                (value ?? "").Trim(), @"[\s.\-()]", "");

            if (phone.StartsWith("+84"))
                phone = "0" + phone.Substring(3);

            return phone;
        }

        private static string NormalizeCode(string value)
        {
            return (value ?? "").Trim().ToUpperInvariant();
        }

        private static bool IsCode(string code)
        {
            return Regex.IsMatch(
                code ?? "", @"^(AT|DV)-[A-F0-9]{16}$");
        }

        private static object OptionalText(string value)
        {
            return string.IsNullOrWhiteSpace(value)
                ? (object)DBNull.Value : value.Trim();
        }

        public static string StatusText(string status)
        {
            switch (status)
            {
                case "PENDING": return "Chờ xác nhận";
                case "CONFIRMED": return "Đã xác nhận";
                case "CANCELLED": return "Đã hủy";
                case "DECLINED": return "Không được xác nhận";
                case "COMPLETED": return "Đã hoàn tất";
                default: return "Đang cập nhật";
            }
        }

        protected override void OnActionExecuting(
            ActionExecutingContext context)
        {
            Response.Cache.SetCacheability(HttpCacheability.NoCache);
            Response.Cache.SetNoStore();
            base.OnActionExecuting(context);
        }

        private void LoadCatalog(BookingPage page)
        {
            page.Today = HotelNow().Date;

            page.Services = database.Database.SqlQuery<ServiceRow>(
                ServiceSelect +
                " WHERE enabled=1 AND service_group=@p0 ORDER BY service_id",
                page.GroupCode).ToList();

            page.Slots = database.Database.SqlQuery<SlotRow>(@"
                SELECT t.slot_id AS Id,t.service_id AS ServiceId,
                    CONVERT(VARCHAR(5),t.start_time,108) AS Time,
                    s.service_name AS ServiceName
                FROM dbo.Dining_Slots t
                JOIN dbo.Dining_Services s ON s.service_id=t.service_id
                WHERE s.enabled=1 AND t.enabled=1
                  AND s.service_group=@p0
                ORDER BY s.service_id,t.start_time",
                page.GroupCode).ToList();
        }

        private string IssueFormToken()
        {
            string token = Guid.NewGuid().ToString("N");
            Session["DiningForm:" + token] =
                DateTime.UtcNow.AddMinutes(30);
            return token;
        }

        private void GrantAccess(string code)
        {
            Session["DiningAccess:" + code] =
                DateTime.UtcNow.AddMinutes(30);
        }

        private bool HasAccess(string code)
        {
            object until = Session["DiningAccess:" + code];
            return until is DateTime
                && (DateTime)until > DateTime.UtcNow;
        }

        private ActionResult OpenOrder(string code)
        {
            return Redirect(
                Url.Action("Lookup", "Dining", new { code = code })
                + "#dining-result");
        }

        private ActionResult FinishSubmission(string token, string code)
        {
            Session["DiningDone:" + token] = code;
            Session.Remove("DiningForm:" + token);
            GrantAccess(code);

            TempData["DiningMessage"] =
                "Đã lưu lịch. Vui lòng lưu mã để tra cứu và kiểm tra bước thanh toán/xác nhận bên dưới.";

            return OpenOrder(code);
        }

        [HttpGet]
        public ActionResult Index(
            string group = "DINING",
            int? serviceId = null,
            string serviceCode = null)
        {
            group = NormalizeGroup(group);
            if (group == null) return HttpNotFound();

            var page = new BookingPage
            {
                GroupCode = group,
                ServiceId = serviceId,
                VisitDate = HotelNow().Date.AddDays(1),
                Guests = 2,
                RequestToken = IssueFormToken()
            };

            LoadCatalog(page);

            if (!serviceId.HasValue
                && !string.IsNullOrWhiteSpace(serviceCode))
            {
                string code = serviceCode.Trim().ToUpperInvariant();
                var match = page.Services.FirstOrDefault(s => s.Code == code);
                if (match != null) page.ServiceId = match.Id;
            }

            if (page.ServiceId.HasValue
                && !page.Services.Any(s => s.Id == page.ServiceId.Value))
            {
                ModelState.AddModelError(
                    "ServiceId",
                    "Dịch vụ không thuộc nhóm đang chọn hoặc đã ngừng nhận đặt.");
            }

            return View(page);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Index(
            [Bind(Include =
                "GroupCode,ServiceId,SlotId,VisitDate,Guests,FullName,Phone,Email,Notes,Agree,RequestToken,PaymentPercent")]
            BookingPage page)
        {
            string group = NormalizeGroup(page.GroupCode);

            if (group == null)
            {
                ModelState.AddModelError("", "Nhóm dịch vụ không hợp lệ.");
                page.GroupCode = "DINING";
                ModelState.Remove("GroupCode");
            }
            else
            {
                page.GroupCode = group;
            }

            page.FullName = (page.FullName ?? "").Trim();
            page.Phone = NormalizePhone(page.Phone);

            Guid token;
            bool validToken = false;

            if (Guid.TryParseExact(page.RequestToken ?? "", "N", out token))
            {
                string done =
                    Session["DiningDone:" + page.RequestToken] as string;

                if (!string.IsNullOrEmpty(done))
                {
                    GrantAccess(done);
                    return OpenOrder(done);
                }

                object until = Session["DiningForm:" + page.RequestToken];
                validToken = until is DateTime
                    && (DateTime)until > DateTime.UtcNow;
            }

            if (!validToken)
            {
                ModelState.AddModelError(
                    "",
                    "Phiên gửi yêu cầu hết hạn. Vui lòng kiểm tra thông tin và gửi lại.");

                page.RequestToken = IssueFormToken();
                ModelState.Remove("RequestToken");
            }

            if (page.FullName.Length < 2)
                ModelState.AddModelError(
                    "FullName", "Vui lòng nhập họ tên từ 2 ký tự.");

            if (!Regex.IsMatch(page.Phone, @"^0[35789][0-9]{8}$"))
                ModelState.AddModelError(
                    "Phone", "Số điện thoại Việt Nam không hợp lệ.");

            if (page.PaymentPercent != 30 && page.PaymentPercent != 100)
                ModelState.AddModelError(
                    "PaymentPercent",
                    "Chọn cọc 30% hoặc thanh toán đủ 100%.");

            if (!page.Agree)
                ModelState.AddModelError(
                    "Agree",
                    "Vui lòng xác nhận đã đọc thông tin đặt dịch vụ.");

            if (page.VisitDate.HasValue)
            {
                DateTime date = page.VisitDate.Value.Date;
                DateTime today = HotelNow().Date;

                if (date < today || date > today.AddDays(90))
                    ModelState.AddModelError(
                        "VisitDate",
                        "Chọn ngày trong khoảng hôm nay đến 90 ngày tới.");
            }

            if (ModelState.IsValid && validToken)
            {
                try
                {
                    using (var tx = database.Database.BeginTransaction(
                        IsolationLevel.Serializable))
                    {
                        database.Database.ExecuteSqlCommand(@"
                            DECLARE @lock INT;
                            EXEC @lock=sys.sp_getapplock
                                @Resource='DiningInventory',
                                @LockMode='Exclusive',
                                @LockOwner='Transaction',
                                @LockTimeout=5000;
                            IF @lock<0
                                THROW 51000,N'Hệ thống đang bận. Vui lòng thử lại.',1;");

                        string previous =
                            database.Database.SqlQuery<string>(@"
                                SELECT public_code
                                FROM dbo.Dining_Reservations
                                    WITH(UPDLOCK,HOLDLOCK)
                                WHERE request_token=@p0",
                                token).SingleOrDefault();

                        if (previous != null)
                        {
                            tx.Commit();
                            return FinishSubmission(
                                page.RequestToken, previous);
                        }

                        var service =
                            database.Database.SqlQuery<ServiceRow>(
                                ServiceSelect +
                                " WITH(HOLDLOCK) WHERE enabled=1 AND service_id=@p0 AND service_group=@p1",
                                page.ServiceId.Value,
                                page.GroupCode).SingleOrDefault();

                        var slot = database.Database.SqlQuery<SlotRow>(@"
                            SELECT slot_id AS Id,service_id AS ServiceId,
                                CONVERT(VARCHAR(5),start_time,108) AS Time
                            FROM dbo.Dining_Slots WITH(HOLDLOCK)
                            WHERE slot_id=@p0 AND service_id=@p1
                              AND enabled=1",
                            page.SlotId.Value,
                            page.ServiceId.Value).SingleOrDefault();

                        if (service == null || slot == null)
                        {
                            ModelState.AddModelError(
                                "",
                                "Dịch vụ hoặc khung giờ không còn nhận đặt. Vui lòng chọn lại.");
                        }
                        else
                        {
                            DateTime visitAt = page.VisitDate.Value.Date.Add(
                                TimeSpan.ParseExact(
                                    slot.Time, @"hh\:mm",
                                    CultureInfo.InvariantCulture));

                            if (visitAt < HotelNow().AddMinutes(30))
                            {
                                ModelState.AddModelError(
                                    "SlotId",
                                    "Vui lòng đặt trước giờ đến ít nhất 30 phút.");
                            }
                            else
                            {
                                if (service.PayOnline)
                                {
                                    byte[] clientHash;

                                    using (var sha = SHA256.Create())
                                    {
                                        clientHash = sha.ComputeHash(
                                            Encoding.UTF8.GetBytes(
                                                Request.UserHostAddress
                                                ?? "unknown"));
                                    }

                                    string held =
                                        database.Database.SqlQuery<string>(@"
                                            EXEC dbo.CreateServiceHold
                                                @token=@p0,
                                                @service_id=@p1,
                                                @slot_id=@p2,
                                                @visit_date=@p3,
                                                @guests=@p4,
                                                @full_name=@p5,
                                                @phone=@p6,
                                                @email=@p7,
                                                @notes=@p8,
                                                @percent=@p9,
                                                @client_hash=@p10",
                                            token,
                                            service.Id,
                                            slot.Id,
                                            page.VisitDate.Value.Date,
                                            page.Guests.Value,
                                            page.FullName,
                                            page.Phone,
                                            OptionalText(page.Email),
                                            OptionalText(page.Notes),
                                            page.PaymentPercent,
                                            clientHash).Single();

                                    tx.Commit();

                                    return FinishSubmission(
                                        page.RequestToken, held);
                                }

                                decimal? total =
                                    service.PricingMode == "PER_PERSON"
                                    ? service.UnitPrice.Value * page.Guests.Value
                                    : (decimal?)null;

                                string code =
                                    (page.GroupCode == "WELLNESS"
                                        ? "DV-" : "AT-")
                                    + Guid.NewGuid().ToString("N")
                                        .Substring(0, 16).ToUpperInvariant();

                                database.Database.ExecuteSqlCommand(@"
                                    INSERT dbo.Dining_Reservations (
                                        public_code,request_token,
                                        service_id,slot_id,
                                        service_group,service_name,
                                        visit_at,guests,
                                        pricing_mode,unit_price,
                                        estimated_total,full_name,
                                        phone,email,notes
                                    )
                                    VALUES (
                                        @p0,@p1,@p2,@p3,@p4,@p5,@p6,@p7,
                                        @p8,@p9,@p10,@p11,@p12,@p13,@p14
                                    )",
                                    code,
                                    token,
                                    service.Id,
                                    slot.Id,
                                    page.GroupCode,
                                    service.Name,
                                    visitAt,
                                    page.Guests.Value,
                                    service.PricingMode,
                                    service.UnitPrice.HasValue
                                        ? (object)service.UnitPrice.Value
                                        : DBNull.Value,
                                    total.HasValue
                                        ? (object)total.Value
                                        : DBNull.Value,
                                    page.FullName,
                                    page.Phone,
                                    OptionalText(page.Email),
                                    OptionalText(page.Notes));

                                tx.Commit();

                                return FinishSubmission(
                                    page.RequestToken, code);
                            }
                        }
                    }
                }
                catch (SqlException ex)
                {
                    ModelState.AddModelError(
                        "",
                        ex.Number == 51000
                            ? ex.Message
                            : "Chưa lưu được yêu cầu. Vui lòng kiểm tra và thử lại.");
                }
            }

            LoadCatalog(page);
            return View(page);
        }

        private ReservationRow FindOrder(string code)
        {
            return database.Database.SqlQuery<ReservationRow>(@"
                SELECT public_code AS Code,
                    service_group AS GroupCode,
                    service_name AS ServiceName,
                    visit_at AS VisitAt,
                    guests AS Guests,
                    pricing_mode AS PricingMode,
                    unit_price AS UnitPrice,
                    estimated_total AS EstimatedTotal,
                    full_name AS FullName,
                    phone AS Phone,email AS Email,
                    notes AS Notes,status AS Status,
                    staff_note AS StaffNote,
                    cancellation_reason AS CancellationReason,
                    created_at_utc AS CreatedAtUtc
                FROM dbo.Dining_Reservations
                WHERE public_code=@p0",
                code).SingleOrDefault();
        }

        [HttpGet]
        public ActionResult Lookup(string code, bool cancel = false)
        {
            code = NormalizeCode(code);
            var page = new LookupPage { Code = code };

            if (IsCode(code) && HasAccess(code))
            {
                if (IsPaymentOrder(code))
                    return RedirectToAction("Payment", new { code });

                page.Order = FindOrder(code);
                if (page.Order == null) return HttpNotFound();

                page.Phone = page.Order.Phone;
                page.CanCancel =
                    (page.Order.Status == "PENDING"
                        || page.Order.Status == "CONFIRMED")
                    && page.Order.VisitAt > HotelNow();

                page.AskCancel = cancel && page.CanCancel;
            }

            return View(page);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Lookup(
            [Bind(Include = "Code,Phone")] LookupPage page)
        {
            page.Code = NormalizeCode(page.Code);
            page.Phone = NormalizePhone(page.Phone);

            if (!IsCode(page.Code))
                ModelState.AddModelError(
                    "Code", "Mã đặt dịch vụ không đúng định dạng.");

            if (!Regex.IsMatch(page.Phone, @"^0[35789][0-9]{8}$"))
                ModelState.AddModelError(
                    "Phone", "Số điện thoại không hợp lệ.");

            if (!ModelState.IsValid) return View(page);

            string found = database.Database.SqlQuery<string>(@"
                SELECT public_code
                FROM dbo.Dining_Reservations
                WHERE public_code=@p0 AND phone=@p1",
                page.Code, page.Phone).SingleOrDefault();

            if (found == null)
            {
                ModelState.AddModelError(
                    "",
                    "Không tìm thấy yêu cầu khớp mã và số điện thoại.");
                return View(page);
            }

            GrantAccess(found);
            return OpenOrder(found);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Cancel(
            string code, string reason, bool confirm = false)
        {
            code = NormalizeCode(code);
            reason = (reason ?? "").Trim();

            if (!IsCode(code) || !HasAccess(code))
                return new HttpStatusCodeResult(403);

            if (!confirm || reason.Length < 3 || reason.Length > 500)
            {
                TempData["DiningMessage"] =
                    "Vui lòng xác nhận hủy và nhập lý do từ 3 đến 500 ký tự.";
                return OpenOrder(code);
            }

            if (IsPaymentOrder(code))
            {
                try
                {
                    database.Database.ExecuteSqlCommand(
                        "EXEC dbo.RequestServiceCancellation @code=@p0,@reason=@p1",
                        code, reason);

                    TempData["DiningMessage"] =
                        "Đã ghi nhận. Lịch chưa trả tiền được hủy; lịch đã trả tiền sẽ chờ khách sạn xét hủy và hoàn tiền.";
                }
                catch (SqlException ex)
                {
                    TempData["DiningMessage"] = ex.Number == 51000
                        ? ex.Message
                        : "Chưa gửi được yêu cầu hủy. Vui lòng thử lại.";
                }

                return RedirectToAction("Payment", new { code });
            }

            int changed = database.Database.ExecuteSqlCommand(@"
                UPDATE dbo.Dining_Reservations
                SET status='CANCELLED',
                    cancellation_reason=@p1,
                    cancelled_at_utc=SYSUTCDATETIME(),
                    updated_at_utc=SYSUTCDATETIME()
                WHERE public_code=@p0
                  AND status IN ('PENDING','CONFIRMED')
                  AND visit_at>@p2",
                code, reason, HotelNow());

            TempData["DiningMessage"] = changed == 1
                ? "Đã hủy yêu cầu. Thông tin vẫn được lưu để tra cứu."
                : "Yêu cầu đã hủy hoặc không còn được hủy trên web.";

            return OpenOrder(code);
        }

        private bool IsPaymentOrder(string code)
        {
            return database.Database.SqlQuery<int>(@"
                SELECT COUNT(*)
                FROM dbo.Dining_ServicePayments p
                JOIN dbo.Dining_Reservations r
                    ON r.reservation_id=p.reservation_id
                WHERE r.public_code=@p0",
                code).Single() > 0;
        }

        public class PaymentRow
        {
            public string Code { get; set; }
            public string ServiceName { get; set; }
            public string GroupCode { get; set; }
            public string ImageUrl { get; set; }
            public DateTime VisitAt { get; set; }
            public int Guests { get; set; }
            public string FullName { get; set; }
            public string Phone { get; set; }
            public string Status { get; set; }
            public string PaymentStatus { get; set; }
            public int Percent { get; set; }
            public decimal Total { get; set; }
            public decimal Required { get; set; }
            public decimal Paid { get; set; }
            public decimal Refunded { get; set; }
            public DateTime HoldUntilUtc { get; set; }
            public DateTime? CancelRequestedAtUtc { get; set; }
            public string StaffNote { get; set; }

            public string Reference
            {
                get { return "ML" + Code.Replace("-", ""); }
            }

            public bool CanTransfer
            {
                get
                {
                    return Status == "PENDING"
                        && Paid == 0
                        && HoldUntilUtc > DateTime.UtcNow
                        && (PaymentStatus == "WAITING"
                            || PaymentStatus == "REPORTED")
                        && !CancelRequestedAtUtc.HasValue;
                }
            }

            public bool CanCancel
            {
                get
                {
                    return (Status == "PENDING"
                            || Status == "CONFIRMED")
                        && VisitAt > HotelNow()
                        && !CancelRequestedAtUtc.HasValue;
                }
            }
        }

        [HttpGet]
        public ActionResult Payment(string code)
        {
            code = NormalizeCode(code);

            if (!IsCode(code) || !HasAccess(code))
                return RedirectToAction("Lookup", new { code });

            var order = database.Database.SqlQuery<PaymentRow>(@"
                SELECT r.public_code AS Code,
                    r.service_name AS ServiceName,
                    r.service_group AS GroupCode,
                    s.image_url AS ImageUrl,
                    r.visit_at AS VisitAt,r.guests AS Guests,
                    r.full_name AS FullName,r.phone AS Phone,
                    r.status AS Status,
                    p.payment_status AS PaymentStatus,
                    p.payment_percent AS [Percent],
                    p.total_amount AS Total,
                    p.required_amount AS Required,
                    p.paid_amount AS Paid,
                    p.refunded_amount AS Refunded,
                    p.hold_until_utc AS HoldUntilUtc,
                    p.cancel_requested_at_utc AS CancelRequestedAtUtc,
                    p.staff_note AS StaffNote
                FROM dbo.Dining_Reservations r
                JOIN dbo.Dining_ServicePayments p
                    ON p.reservation_id=r.reservation_id
                JOIN dbo.Dining_Services s
                    ON s.service_id=r.service_id
                WHERE r.public_code=@p0",
                code).SingleOrDefault();

            if (order == null) return HttpNotFound();
            return View(order);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult ReportTransfer(string code)
        {
            code = NormalizeCode(code);

            if (!IsCode(code) || !HasAccess(code))
                return new HttpStatusCodeResult(403);

            try
            {
                database.Database.ExecuteSqlCommand(
                    "EXEC dbo.ReportServiceTransfer @code=@p0", code);

                TempData["DiningMessage"] =
                    "Đã báo khách sạn đối soát. Lịch chỉ được xác nhận khi ngân hàng ghi nhận tiền và vẫn còn chỗ.";
            }
            catch (SqlException ex)
            {
                TempData["DiningMessage"] = ex.Number == 51000
                    ? ex.Message
                    : "Chưa gửi được thông báo. Vui lòng thử lại.";
            }

            return RedirectToAction("Payment", new { code });
        }

        public class AvailabilityRow
        {
            public int Id { get; set; }
            public string Time { get; set; }
            public int Remaining { get; set; }
        }

        [HttpGet]
        public ActionResult Availability(int serviceId, DateTime? date)
        {
            if (!date.HasValue
                || date.Value.Date < HotelNow().Date
                || date.Value.Date > HotelNow().Date.AddDays(90))
                return new HttpStatusCodeResult(400);

            var rows = database.Database.SqlQuery<AvailabilityRow>(@"
                SELECT t.slot_id AS Id,
                    CONVERT(VARCHAR(5),t.start_time,108) AS Time,
                    i.capacity-dbo.ServiceOccupied(
                        s.service_id,
                        DATEADD(
                            SECOND,
                            DATEDIFF(
                                SECOND,CONVERT(TIME,'00:00'),
                                t.start_time
                            ),
                            @p1
                        ),
                        i.duration_minutes,0
                    ) AS Remaining
                FROM dbo.Dining_Slots t
                JOIN dbo.Dining_Services s
                    ON s.service_id=t.service_id
                JOIN dbo.Dining_ServiceInventory i
                    ON i.service_id=s.service_id
                WHERE s.service_id=@p0
                  AND s.enabled=1 AND i.enabled=1 AND t.enabled=1
                  AND s.pricing_mode='PER_PERSON'
                  AND s.unit_price>0
                  AND DATEADD(
                      SECOND,
                      DATEDIFF(
                          SECOND,CONVERT(TIME,'00:00'),t.start_time
                      ),
                      @p1
                  )>=@p2
                ORDER BY t.start_time",
                serviceId,
                date.Value.Date,
                HotelNow().AddMinutes(30)).ToList();

            return Json(rows, JsonRequestBehavior.AllowGet);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) database.Dispose();
            base.Dispose(disposing);
        }
    }
}